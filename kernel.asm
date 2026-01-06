[ORG 0x8000]
[BITS 16]

kernel_start:
    ; --- 16-bit Setup ---
    in al, 0x92
    or al, 2
    out 0x92, al ; Enable A20

    ; Identity Paging Setup
    mov di, 0x1000
    xor ax, ax
    mov cx, 0x3000
    rep stosb

    mov dword [0x1000], 0x2003
    mov dword [0x2000], 0x3003
    mov dword [0x3000], 0x83

    ; GDT & Switch
    lgdt [gdt_descriptor]
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax
    mov eax, 0x1000
    mov cr3, eax
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr
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
    
    ; Reconfigure PIT Ch0 for precise timing (Mode 2, LSB/MSB, Count 0x0000=65536)
    ; This fixes timing if BIOS left it in a weird state
    mov al, 0x34 ; Ch0, Access Lo/Hi, Mode 2, Bin
    out 0x43, al
    xor al, al
    out 0x40, al ; Lo
    out 0x40, al ; Hi

    call clear_screen

    mov rsi, music_data

play_loop:
    xor rax, rax
    lodsw           ; Duration (low 16)
    mov rbx, rax
    
    lodsw           ; Divisor (high 16)
    mov rcx, rax
    
    lodsw           ; Channel (Color info)
    mov rdx, rax 
    
    ; End check (Dur=0, Div=0, Chan=0)
    mov r8, rbx
    or r8, rcx
    or r8, rdx
    jz hang
    
    ; Divisor 0 = Silence
    test rcx, rcx
    jz .silence
    
    ; --- Sound ON ---
    mov rax, rcx ; Divisor
    
    ; Load PIT Ch2 (Speaker)
    push rax
    mov al, 0xB6
    out 0x43, al
    pop rax
    
    out 0x42, al ; Low
    mov al, ah
    out 0x42, al ; High
    
    ; Speaker ON
    in al, 0x61
    or al, 3
    out 0x61, al
    
    ; Visualize Note (Scrolls Screen)
    mov rdi, rcx  ; Divisor
    mov rsi, rdx  ; Channel (Color)
    call visualize_note
    
    ; Update Debug Info (Status Bar - Redraw after scroll)
    push rbx
    push rcx
    call print_debug_info
    pop rcx
    pop rbx
    
    jmp .wait

.silence:
    ; Speaker OFF
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    
    call scroll_screen
    
    ; Update Debug (Silence)
    push rbx
    push rcx
    call print_debug_info
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

; -----------------------------------------------
; Debug Info: Prints DUR:XXXX DIV:XXXX at top right
; Input: RBX=Dur, RCX=Div
; -----------------------------------------------
print_debug_info:
    mov rdi, 0xB8000 + 120 ; Near top right
    
    mov rax, 0x0F520F550F44 ; "DUR"
    mov [rdi], rax
    add rdi, 6
    mov word [rdi], 0x0F3A ; ":"
    add rdi, 2
    
    mov rax, rbx
    call print_hex_word
    
    add rdi, 2
    mov word [rdi], 0x0F20 ; " "
    add rdi, 2
    
    mov rax, 0x0F560F490F44 ; "DIV"
    mov [rdi], rax
    add rdi, 6
    mov word [rdi], 0x0F3A ; ":"
    add rdi, 2
    
    mov rax, rcx
    call print_hex_word
    ret

; Print AX as 4 Hex digits to [RDI], advances RDI
print_hex_word:
    push rcx
    push rax
    
    ; Nibble 4 (Top)
    mov rcx, rax
    shr rcx, 12
    call print_nibble
    
    ; Nibble 3
    mov rcx, rax
    shr rcx, 8
    call print_nibble
    
    ; Nibble 2
    mov rcx, rax
    shr rcx, 4
    call print_nibble
    
    ; Nibble 1
    mov rcx, rax
    call print_nibble
    
    pop rax
    pop rcx
    ret

print_nibble:
    and rcx, 0xF
    cmp rcx, 9
    jle .num
    add rcx, 'A'-10
    jmp .write
.num:
    add rcx, '0'
.write:
    mov ah, 0x4F ; Red on White for visibility
    mov al, cl
    mov [rdi], ax
    add rdi, 2
    ret


; -----------------------------------------------
; Visualizer: Green bar based on pitch
; -----------------------------------------------
visualize_note:
    push rdi
    call scroll_screen
    pop rdi
    
    ; Logic: Position = 79 - (Divisor / 128)
    shr rdi, 7
    mov rax, 79
    sub rax, rdi
    
    ; Clamp
    cmp rax, 0
    jge .ok1
    mov rax, 0
.ok1:
    cmp rax, 79
    jle .ok2
    mov rax, 79
.ok2:
    
    ; Calc address: 0xB8000 + (24*80 + x)*2
    shl rax, 1
    add rax, 3840
    add rax, 0xB8000
    
    ; Determine Color from Channel (RSI)
    ; RSI contains Channel (0-15).
    ; VGA Colors 1-15 are good. 0 is Black (no good).
    ; We'll do (Channel % 15) + 1. Channels are usually 0-15 anyway.
    mov r8, rsi
    and r8, 0xF ; 0-15
    inc r8      ; 1-16 (If 16 -> 0? No, 15+1=16. 16 is Blink Black? No 0-15 is FG)
    
    ; Wait, VGA attribute byte: [Blink][BG][BG][BG][FG][FG][FG][FG]
    ; If FG > 15 (e.g. 16) it spills to BG or Blink.
    ; So mask with 0xF. If 0 -> 1.
    and r8, 0xF
    jnz .col_ok
    mov r8, 1 ; Default Blue
.col_ok:
    
    ; Construct Attribute: 0000 (Black BG) + Color (FG)
    ; AH = Attribute
    mov al, 0x23 ; '#'    
    mov [rax], al ; Char
    mov [rax+1], r8b ; Attribute (Color)
    ret

scroll_screen:
    push rax
    push rcx
    push rsi
    push rdi
    
    cld
    mov rsi, 0xB8000 + 160
    mov rdi, 0xB8000
    mov rcx, 480 ; 3840 / 8
    rep movsq
    
    ; Clear last line
    mov rdi, 0xB8000 + 3840
    mov rax, 0x0720072007200720 ; Spaces
    mov rcx, 20 ; 160 / 8
    rep stosq
    
    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

clear_screen:
    push rax
    push rcx
    push rdi

    mov rdi, 0xB8000
    mov rax, 0x0720072007200720
    mov rcx, 500 ; 4000 / 4 ? Total 80*25*2 = 4000. 4000/8 = 500
    mov rcx, 500
    rep stosq
    
    pop rdi
    pop rcx
    pop rax
    ret

delay_ms:
    test rdi, rdi
    jz .done
    ; Calibrate: 1ms = 1193 ticks
    push rsi
.loop:
    push rdi
    
    ; Wait 1ms
    mov al, 0
    out 0x43, al ; Latch Ch0
    in al, 0x40
    mov bl, al
    in al, 0x40
    mov bh, al ; BX = Start
    
    mov rsi, 1193
.poll:
    mov al, 0
    out 0x43, al
    in al, 0x40
    mov dl, al
    in al, 0x40
    mov dh, al ; DX = Curr
    
    mov ax, bx
    sub ax, dx ; Elastpsed
    cmp ax, si
    jb .poll
    
    pop rdi
    dec rdi
    jnz .loop
    pop rsi
.done:
    ret

align 8
gdt_start: dq 0
gdt_code: dq 0x00209A0000000000
gdt_data: dq 0x0000920000000000
gdt_end:
gdt_descriptor: dw gdt_end - gdt_start - 1
                dq gdt_start

; Include Music Binary directly to ensure alignment and presence
align 16
music_data:
    incbin "sonic.bin"
    dw 0, 0 ; Safety Terminator in case bin is broken
