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

    ; 1. Scroll Screen Up
    ; Move 0xB80A0 (Line 1) -> 0xB8000 (Line 0) for 24 lines
    mov rsi, 0xB8000 + 160 ; Source: Line 1
    mov rdi, 0xB8000       ; Dest: Line 0
    mov rcx, 1920          ; 80 chars * 24 lines = 1920 qwords (Wait, 80*24*2=3840 bytes. 3840/8=480 qwords)
                           ; Let's use words for safety. 80*24 = 1920 words.
    mov rcx, 1920
    rep movsw

    ; 2. Clear Bottom Line
    mov rdi, 0xB8000 + (160 * 24) ; Start of 25th line
    mov ax, 0x0720 ; Space (0x20) with Grey (0x07)
    mov rcx, 80
    rep stosw

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
    
    ; Write Char
    mov ah, al     ; Attribute (Color)
    mov al, 0x23   ; Char '#'
    mov [rdi], ax

.done_vis:
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
    mov ax, 0x0720
    mov rcx, 2000 ; 80*25
    rep stosw
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
