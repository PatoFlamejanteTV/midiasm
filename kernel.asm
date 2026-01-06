[ORG 0x8000]

[BITS 16]
kernel_start:
    ; Enable A20
    in al, 0x92
    or al, 2
    out 0x92, al

    ; Prepare Paging
    mov di, 0x1000
    xor ax, ax
    mov cx, 0x3000
    rep stosb

    mov dword [0x1000], 0x2003 ; PML4 -> PDP
    mov dword [0x2000], 0x3003 ; PDP -> PD
    mov dword [0x3000], 0x83   ; PD -> 2MB Page (Identity 0-2MB)

    ; Load GDT
    lgdt [gdt_descriptor]

    ; Enable PAE
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; Load CR3
    mov eax, 0x1000
    mov cr3, eax

    ; Enable Long Mode
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    ; Enable Paging and PE
    mov eax, cr0
    or eax, (1 << 31) | 1
    mov cr0, eax

    jmp 0x08:long_mode_start

[BITS 64]
long_mode_start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    ; Clear Screen
    call clear_screen

    ; Start Music
    mov rsi, music_data

play_loop:
    xor rax, rax
    lodsw           ; Duration
    mov rbx, rax
    
    lodsw           ; Divisor
    mov rcx, rax
    
    test rbx, rbx
    jnz .check_play
    test rcx, rcx
    jz hang
    
.check_play:
    test rcx, rcx
    jz .silence
    
    ; Visualize Current Note
    push rbx
    push rcx
    mov rdi, rcx ; Divisor
    call visualize_note
    pop rcx
    pop rbx

    ; Play Sound
    mov al, 0xB6
    out 0x43, al
    mov al, cl
    out 0x42, al
    mov al, ch
    out 0x42, al
    
    in al, 0x61
    or al, 3
    out 0x61, al
    jmp .wait

.silence:
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    
    ; Visualize Silence (Scroll but empty line)
    push rbx
    push rcx
    call scroll_screen
    pop rcx
    pop rbx

.wait:
    mov rdi, rbx
    call delay_ms
    jmp play_loop

hang:
    in al, 0x61
    and al, 0xFC
    out 0x61, al
.halt:
    hlt
    jmp .halt

; ---------------------------------------------------------
; Visualizer Routine
; Input: RDI = Divisor
; Logic:
;   1. Scroll Screen Up
;   2. Calculate X position from Divisor
;   3. Draw Point
; ---------------------------------------------------------
visualize_note:
    push rdi
    call scroll_screen
    pop rdi
    
    ; Calculate Position
    ; Divisor Range: ~1000 (High) to ~10000 (Low)
    ; Screen Width: 80
    ; Let's map Divisor to 0-79.
    ; Formula: Pos = (Divisor - 1000) / 100 ?
    ; Simple shift: Pos = Divisor >> 7 (div 128)
    ; 10000 >> 7 = 78
    ; 1000 >> 7 = 7
    ; This fits 0-79 well!
    ; Invert? Piano: Low freq (Left) -> High Freq (Right).
    ; High Divisor = Low Freq. So High Divisor = Left (0).
    ; Current: High Divisor = 78 (Right).
    ; So we want: Pos = 79 - (Divisor >> 7)
    
    shr rdi, 7
    mov rax, 79
    sub rax, rdi
    
    ; Clamp 0-79
    cmp rax, 0
    jge .ok_min
    mov rax, 0
.ok_min:
    cmp rax, 79
    jle .ok_max
    mov rax, 79
.ok_max:
    
    ; Draw at last line (Row 24)
    ; Offset = (24 * 80 + col) * 2
    ; Row 24 start = 3840
    shl rax, 1 ; * 2 bytes per char
    add rax, 3840
    add rax, 0xB8000
    
    ; Write Char
    ; 0x0F = White, 0x09 = Blue, 0x0A = Green?
    ; Let's cycle colors or use Green
    mov word [rax], 0x0A0F ; 0x0A (Green FG), 0x0F (Symbol Sun thing?)
    ; Wait, attribute is byte 2. Char is byte 1.
    ; mov word [ptr], 0xAttrChar
    ; 0x0A = Green. Char = 'O' (0x4F)
    mov word [rax], 0x0A4F ; 'O' in Green
    ret

scroll_screen:
    ; Move 0xB8000+160 -> 0xB8000
    ; Size: 80*24*2 = 3840 bytes.
    ; Count qwords: 3840/8 = 480
    
    cld
    mov rsi, 0xB8000 + 160
    mov rdi, 0xB8000
    mov rcx, 480
    rep movsq
    
    ; Clear last line (0xB8000 + 3840 to +4000)
    ; 160 bytes / 8 = 20 qwords
    mov rdi, 0xB8000 + 3840
    mov rax, 0x0000000000000000 ; Space 0x00 ?? No space is 0x20
    ; Blank char: 0x20 (space), 0x07 (Light Grey) -> 0x0720
    ; Qword = 0x0720072007200720
    mov rax, 0x0720072007200720
    mov rcx, 20
    rep stosq
    ret

clear_screen:
    mov rdi, 0xB8000
    mov rax, 0x0720072007200720
    mov rcx, 500 ; 80*25*2 / 8
    rep stosq
    ret
    
delay_ms:
    test rdi, rdi
    jz .done
.ms_loop:
    push rdi
    mov rdi, 1193
    call wait_pit
    pop rdi
    dec rdi
    jnz .ms_loop
.done:
    ret

wait_pit:
    mov al, 0x00
    out 0x43, al
    in al, 0x40
    mov bl, al
    in al, 0x40
    mov bh, al
.poll:
    mov al, 0x00
    out 0x43, al
    in al, 0x40
    mov dl, al
    in al, 0x40
    mov dh, al
    mov ax, bx
    sub ax, dx
    cmp ax, di
    jb .poll
    ret

align 8
gdt_start:
    dq 0
gdt_code:
    dq 0x00209A0000000000
gdt_data:
    dq 0x0000920000000000
gdt_end:
gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dq gdt_start

; Determine start of music (concatenated after this bin)
align 16
music_data:
