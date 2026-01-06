[BITS 16]
[ORG 0x7C00]

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; Print "Booting..."
    mov si, msg_boot
    call print_string

    ; Load payload (Music Data) from disk to 0x8000
    mov ah, 0x02    ; Read sectors
    mov al, 64      ; Count (32KB)
    mov ch, 0       ; Cyl
    mov cl, 2       ; Sec (1-based, 2 is next)
    mov dh, 0       ; Head
    mov bx, 0x8000  ; Dest
    int 0x13
    jc disk_error
    
    mov si, msg_loaded
    call print_string

    ; Enable A20 Line (Fast method)
    in al, 0x92
    or al, 2
    out 0x92, al

    ; Prepare Paging (Identity Map first 2MB)
    mov di, 0x1000
    xor ax, ax
    mov cx, 0x3000
    rep stosb

    ; PML4 [0x1000] -> PDP [0x2000]
    mov dword [0x1000], 0x2003 ; Present, RW
    
    ; PDP [0x2000] -> PD [0x3000]
    mov dword [0x2000], 0x3003
    
    ; PD [0x3000] -> 2MB Page 0
    mov dword [0x3000], 0x83   ; Present, RW, Huge(2MB)

    ; Load GDT
    lgdt [gdt_descriptor]

    ; Enable PAE in CR4
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; Load CR3
    mov eax, 0x1000
    mov cr3, eax

    ; Enable Long Mode in EFER MSR (0xC0000080)
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    ; Enable Paging (Bit 31) and Protected Mode (Bit 0)
    mov eax, cr0
    or eax, (1 << 31) | 1
    mov cr0, eax

    ; Far jump to 64-bit code
    jmp 0x08:long_mode_start

disk_error:
    mov si, msg_error
    call print_string
    jmp $

print_string:
    mov ah, 0x0E
.loop:
    lodsb
    test al, al
    jz .done
    int 0x10
    jmp .loop
.done:
    ret

msg_boot db "Boot...", 13, 10, 0
msg_loaded db "OK, Go 64...", 13, 10, 0
msg_error db "Err!", 13, 10, 0

[BITS 64]
long_mode_start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    ; Visual Indicator in Video Memory (White 'P' on Blue at top left)
    mov word [0xB8000], 0x1F50 ; 'P'
    mov word [0xB8002], 0x1F4C ; 'L'
    mov word [0xB8004], 0x1F41 ; 'A'
    mov word [0xB8006], 0x1F59 ; 'Y'

    mov rsi, 0x8000

play_loop:
    ; Data Format: int16 Duration_ms, int16 Divisor
    xor rax, rax
    lodsw           ; Load Duration (low 16)
    mov rbx, rax    ; Save Duration in RBX
    
    lodsw           ; Load Divisor
    mov rcx, rax    ; Divisor in RCX
    
    ; Check for end of stream (Duration=0 and Divisor=0)
    test rbx, rbx
    jnz .check_play
    test rcx, rcx
    jz hang ; End
    
.check_play:
    test rcx, rcx
    jz .silence     ; Divisor 0 = Silence
    
    ; Play Sound (Square Wave)
    ; Set Divisor
    mov al, 0xB6
    out 0x43, al
    mov al, cl
    out 0x42, al
    mov al, ch
    out 0x42, al
    
    ; Enable Speaker (Bits 0 and 1 of 0x61)
    in al, 0x61
    or al, 3
    out 0x61, al
    jmp .wait

.silence:
    in al, 0x61
    and al, 0xFC ; Clear bits 0,1
    out 0x61, al

.wait:
    ; Wait for RBX milliseconds
    mov rdi, rbx
    call delay_ms
    jmp play_loop

hang:
    ; Silence and Halt
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    ; Print 'D'ONE
    mov word [0xB8008], 0x1F20
    mov word [0xB800A], 0x1F44 
    mov word [0xB800C], 0x1F4F
    mov word [0xB800E], 0x1F4E
    mov word [0xB8010], 0x1F45
.halt:
    hlt
    jmp .halt

; Function: delay_ms
; Input: RDI = milliseconds
delay_ms:
    test rdi, rdi
    jz .done
    
    ; Loop RDI times
.ms_loop:
    push rdi
    ; Wait 1ms (approx 1193 ticks of PIT)
    mov rdi, 1193
    call wait_pit
    pop rdi
    dec rdi
    jnz .ms_loop
.done:
    ret

; Function: wait_pit
; Input: RDI = ticks to wait
wait_pit:
    ; Read initial PIT Ch0
    mov al, 0x00 ; Latch Ch0
    out 0x43, al
    in al, 0x40
    mov bl, al
    in al, 0x40
    mov bh, al ; BX = start count
    
.poll_loop:
    ; Read current
    mov al, 0x00
    out 0x43, al
    in al, 0x40
    mov dl, al
    in al, 0x40
    mov dh, al ; DX = current count
    
    ; Elapsed = Start - Current (since it counts down)
    mov ax, bx
    sub ax, dx
    
    cmp ax, di
    jb .poll_loop ; If elapsed < target, keep polling
    ret

align 8
gdt_start:
    dq 0x0000000000000000 ; Null
gdt_code:
    dq 0x00209A0000000000 ; Code 64-bit, Present, Ring 0, Exec/Read
gdt_data:
    dq 0x0000920000000000 ; Data 64-bit
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dq gdt_start

; Padding to 510
times 510-($-$$) db 0
dw 0xAA55
