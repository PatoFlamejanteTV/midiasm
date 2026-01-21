[ORG 0x8000]
[BITS 16]

kernel_entry:
    ; --- 16-bit Initialization ---
    cli            ; Disable interrupts
    cld            ; Clear direction flag (Forward string ops)

    ; Enable A20 Line
    in al, 0x92
    or al, 2
    out 0x92, al

    ; Create Page Tables (Identity Map 0-2MB) at 0x1000
    mov di, 0x1000
    xor ax, ax
    mov cx, 0x1000 ; Clear 4KB * 4 (enough for simple tables)
    rep stosb

    ; PML4[0] -> PDP
    mov dword [0x1000], 0x2003
    ; PDP[0] -> PD
    mov dword [0x2000], 0x3003
    ; PD[0] -> 2MB Page (Physical 0)
    mov dword [0x3000], 0x83

    ; GDT (Global Descriptor Table)
    lgdt [gdt_desc]

    ; Enable PAE (Physical Address Extension) in CR4
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; Load Page Directory Base into CR3
    mov eax, 0x1000
    mov cr3, eax

    ; Enable Long Mode in EFER MSR
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    ; Enable Paging (PG) and Protected Mode (PE) in CR0
    mov eax, cr0
    or eax, (1 << 31) | 1
    mov cr0, eax

    ; Far Jump to 64-bit Land
    jmp 0x08:long_mode_entry

[BITS 64]
long_mode_entry:
    ; --- 64-bit Initialization ---
    cli
    cld
    mov rsp, 0x7C00  ; Stack grows down from bootloader start

    ; Load Segments
    mov ax, 0x10     ; Data Segment
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    ; Initialize Timer (PIT Ch0) for accurate delay
    mov al, 0x34     ; Mode 2, LSB/MSB
    out 0x43, al
    mov al, 0
    out 0x40, al     ; LSB 0
    out 0x40, al     ; MSB 0

    ; Initialize Visuals
    call decompress_bg
    call clear_vga

    ; --- Main Music Loop ---
    ; Register Usage:
    ; RSI: Pointer to Music Data (PERSISTENT)
    ; R8:  Current Duration
    ; R9:  Current Divisor
    ; R10: Current Color/Channel
    
    mov rsi, music_data

.next_note:
    ; Read Duration (2 bytes)
    xor rax, rax
    lodsw
    mov r8, rax

    ; Read Divisor (2 bytes)
    lodsw
    mov r9, rax

    ; Read Channel/Color (2 bytes) - New Format
    lodsw
    mov r10, rax

    ; Check for Terminator (All Zero)
    mov rax, r8
    or rax, r9
    or rax, r10
    jz .hang

    ; --- Debug Output (Safe Mode) ---
    ; Print raw values to top left to prove we are reading correct data
    mov rdi, 0xB8000
    mov rax, r8
    call print_hex_dbg
    add rdi, 2
    mov rax, r9
    call print_hex_dbg
    add rdi, 2
    mov rax, r10
    call print_hex_dbg

    ; --- Visualizer (Scroll & Draw) ---
    call visualizer_update

    ; --- Sound ---
%ifdef NOISE_BUILD
    test r9, r9
    jz .silence_noise

    ; Sound ON (Noise Mode)
    mov rcx, r8 ; Duration
    call play_noise_note
    ; play_noise_note handles the delay internally
    jmp .next_note

.silence_noise:
    mov rcx, r8
    call pit_delay
    jmp .next_note

%else
    test r9, r9
    jz .silence

    ; Sound ON
    mov rax, r9
    push rax
    mov al, 0xB6
    out 0x43, al
    pop rax
    out 0x42, al
    mov al, ah
    out 0x42, al
    
    in al, 0x61
    or al, 3
    out 0x61, al
    jmp .wait_dur

.silence:
    ; Sound OFF
    in al, 0x61
    and al, 0xFC
    out 0x61, al

.wait_dur:
    ; Delay using PIT
    mov rcx, r8
    call pit_delay
    
    jmp .next_note
%endif

.hang:
    ; Turn off sound and halt
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    hlt
    jmp .hang

; -------------------------------------------------------------
; SUBROUTINES (Must preserve RSI, R8, R9, R10)
; -------------------------------------------------------------

visualizer_update:
    ; Save Critical Registers
    push rsi
    push r8
    push r9
    push r10
    push rdi
    push rcx
    push rax
    push rbx
    push rdx

    ; 1. Scroll Screen Up (Smart Scroll: Move FG, Keep BG static)
    ; We iterate 1920 cells (Lines 0-23)
    mov rsi, 0xB8000 + 160 ; Source (Line 1 char)
    mov rdi, 0xB8000       ; Dest (Line 0 char)
    mov rbx, 0x6000        ; BG Buffer (Start at Line 0)
    mov rcx, 1920

.scroll_loop:
    lodsw                  ; AL=Char, AH=Attr (from Line Y+1)
    
    ; We want: NewChar = Char(Y+1)
    ;          NewAttr = FG(Y+1) | BG(Y_Dest)
    
    mov dl, [rbx]          ; Get Static BG Color for Dest position
    inc rbx
    
    shl dl, 4              ; Move to high nibble
    and ah, 0x0F           ; Keep FG from source
    or ah, dl              ; Combine with Static BG
    
    stosw
    loop .scroll_loop

    ; 2. Clear Bottom Line (Line 24)
    ; rbx now points to start of BG Buffer for Line 24
    ; rdi points to start of VGA Line 24
    mov rcx, 80
.clear_btm:
    mov dl, [rbx]          ; Get BG Color
    inc rbx
    
    shl dl, 4
    or dl, 0x07            ; Light Grey FG (Empty text color)
    mov ah, dl
    mov al, 0x20           ; Space Char
    stosw
    loop .clear_btm

    ; 3. Draw Note
    ; If Divisor (R9) == 0, skip
    cmp r9, 0
    je .done_vis

    ; Calculate Position
    ; Pos = 79 - (Divisor / 128)
    mov rax, r9
    shr rax, 7 ; /128
    mov rbx, 79
    sub rbx, rax
    
    ; Clamp 0-79
    cmp rbx, 0
    jge .c1
    mov rbx, 0
.c1:
    cmp rbx, 79
    jle .c2
    mov rbx, 79
.c2:
    
    ; Address = Start of Bottom Line + (Pos * 2)
    mov rdi, 0xB8000 + (160 * 24)
    shl rbx, 1
    add rdi, rbx
    
    ; Determine Color from Channel (R10)
    mov rax, r10
    and rax, 0xF ; 0-15
    inc rax      ; 1-16
    ; If > 15, default to 1 (Blue)
    cmp rax, 15
    jle .col_ok
    mov rax, 1
.col_ok:
    ; RAX has FG Color Index
    
    ; Get BG Color for this cell
    ; Map VRAM addr back to Buffer index
    ; Buffer Index = (VRAM - 0xB8000) / 2
    push rbx
    mov rbx, rdi
    sub rbx, 0xB8000
    shr rbx, 1
    add rbx, 0x6000   ; 0x6000 is BG Buffer Base
    mov dl, [rbx]     ; DL = BG Color Index
    pop rbx
    
    shl dl, 4
    and al, 0xF       ; Ensure only FG bits
    or al, dl         ; Combine
    
    ; Write Char
    mov ah, al     ; Attribute (Color)
    mov al, 0x01   ; Smiley Face
    mov [rdi], ax

.done_vis:
    pop rdx
    pop rbx
    pop rax
    pop rcx
    pop rdi
    pop r10
    pop r9
    pop r8
    pop rsi
    ret

pit_delay:
    ; Input: RCX = Milliseconds
    ; Uses: RAX, RDX
    push rcx
.ms_loop:
    test rcx, rcx
    jz .end_delay

    ; Setup PIT for ~1ms wait check
    ; Ideally we poll, but let's just loop a safe amount of RDTSC or simplified polling
    ; Polling PIT count:
    push rcx
    
    mov al, 0
    out 0x43, al ; Latch
    in al, 0x40
    mov bl, al
    in al, 0x40
    mov bh, al   ; BX = Start Count
    
    mov dx, 1193
    mov r10w, dx ; Target

.poll:
    mov al, 0
    out 0x43, al
    in al, 0x40
    mov cl, al
    in al, 0x40
    mov ch, al
    
    mov ax, bx
    sub ax, cx
    cmp ax, r10w
    jb .poll
    
    pop rcx
    dec rcx
    jmp .ms_loop
    pop rcx
    dec rcx
    jmp .ms_loop

.end_delay:
    pop rcx
    ret

%ifdef NOISE_BUILD
play_noise_note:
    ; Input: RCX = Duration (ms), R9 = Pitch Divisor
    ; Preserves: RSI
    push rbx
    push rdx
    push r14
    push r15

    ; Enable Speaker Bit 1 Control (Disable Timer 2 Gate)
    in al, 0x61
    and al, 0xFC
    or al, 2      ; Initial state High
    out 0x61, al
    
    xor r14, r14 ; Phase counter

.n_ms_loop:
    test rcx, rcx
    jz .n_done
    
    ; Start 1ms poll
    mov al, 0
    out 0x43, al
    in al, 0x40
    mov bl, al
    in al, 0x40
    mov bh, al   ; BX = Start Count
    
    mov r15w, 1193 ; Target 1ms count
    
.n_poll:
    ; Read Current
    mov al, 0
    out 0x43, al
    in al, 0x40
    mov dl, al
    in al, 0x40
    mov dh, al   ; DX = Current Count
    
    ; Elapsed = BX - DX
    mov ax, bx
    sub ax, dx
    
    cmp ax, r15w
    jae .n_ms_done
    
    ; Noise Toggle Check
    ; R9 contains Divisor (Pitch).
    ; We check if AX (Elapsed) >= R14W (Next Toggle)
    cmp ax, r14w
    jb .n_poll
    
    ; Toggle Speaker
    ; Use RDTSC for randomness
    rdtsc
    test al, 1
    jz .n_low
    in al, 0x61
    or al, 2
    out 0x61, al
    jmp .n_set_next
.n_low:
    in al, 0x61
    and al, ~2
    out 0x61, al
    
.n_set_next:
    add r14w, r9w
    jmp .n_poll
    
.n_ms_done:
    sub r14w, 1193 ; Adjust phase for next MS
    dec rcx
    jmp .n_ms_loop
    
.n_done:
    ; Off
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    
    pop r15
    pop r14
    pop rdx
    pop rbx
    ret
%endif

print_hex_dbg:
    ; Print RAX (low 16 bits) to [RDI]
    push rax
    push rbx
    push rcx
    
    mov rbx, rax
    mov rcx, 4 ; 4 digits
.digit_loop:
    rol bx, 4
    mov al, bl
    and al, 0xF
    cmp al, 9
    jle .is_num
    add al, 'A'-10
    jmp .store
.is_num:
    add al, '0'
.store:
    mov ah, 0x0F ; White on Black
    mov [rdi], ax
    add rdi, 2
    dec rcx
    jnz .digit_loop
    
    pop rcx
    pop rbx
    pop rax
    ret

clear_vga:
    mov rdi, 0xB8000
    mov rsi, 0x6000     ; BG Buffer
    mov rcx, 2000       ; 80*25
.cl_loop:
    lodsb               ; Load BG Color (0-7)
    shl al, 4           ; Shift to high nibble
    or al, 0x07         ; Light Grey FG
    mov ah, al          ; Attribute
    mov al, 0x20        ; Space
    stosw
    loop .cl_loop
    ret

decompress_bg:
    mov rsi, bg_data
    mov rdi, 0x6000     ; Decompression buffer (Safe RAM)
    xor rcx, rcx
.decomp_loop:
    lodsw               ; Load AL=Count, AH=Color
    test al, al         ; Check terminator
    jz .done
    
    mov cl, al          ; Count
    mov al, ah          ; Color
.store_run:
    stosb               ; Buffer stores 1 byte per cell (Color Index)
    dec cl
    jnz .store_run
    
    jmp .decomp_loop
.done:
    ret

; DATA
align 8
gdt_start: dq 0
gdt_code: dq 0x00209A0000000000
gdt_data: dq 0x0000920000000000
gdt_end:
gdt_desc: dw gdt_end - gdt_start - 1
          dq gdt_start

align 16
music_data:
    incbin "sonic.bin"
    times 16 db 0 ; Padding/Terminator

align 16
bg_data:
    incbin "bg.bin"
    db 0, 0 ; Terminator
