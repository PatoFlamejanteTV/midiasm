[BITS 16]
[ORG 0x7C00]

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; Load payload (Music Data) from disk to 0x8000
    ; We assume the payload is immediately after the boot sector
    ; Load 64 sectors (32KB), sufficient for most simple converted MIDIs
    mov ah, 0x02    ; Read sectors
    mov al, 64      ; Count
    mov ch, 0       ; Cyl
    mov cl, 2       ; Sec (1-based, 2 is next)
    mov dh, 0       ; Head
    mov bx, 0x8000  ; Dest
    int 0x13
    ; We ignore errors for "optimization" (minimal code), assuming valid disk

    ; Enable A20 Line (Fast method)
    in al, 0x92
    or al, 2
    out 0x92, al

    ; Prepare Paging (Identity Map first 2MB)
    ; Clear 0x1000-0x4000
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

    ; Enable Paging in CR0
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ; Far jump to 64-bit code
    jmp 0x08:long_mode_start

[BITS 64]
long_mode_start:
    ; Setup Segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    ; Point RSI to data
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
    ; Limit=0, Base=0, Access=9A (P=1, DPL=00, S=1, E=1, DC=0, RW=1, A=0) -> 0x9A
    ; Flags=2 (L=1, DB=0) -> 0x2
    ; Encoded: 0020 9800 0000 0000
    ; Binary:
    ; 0000 0000 0010 0000 1001 1000 0000 0000 ...
    ; Wait, standard GDT 64:
    ; Access: 10011010b = 0x9A
    ; Flags: 0010b (L=1)= 0x2
    ; Let's double check bits.
    ; Byte 5 (Access): 0x9A
    ; Byte 6 (Flags/Lim): 0xAF (4K units)? No, L=1, DB=0. 
    ; Nasm simplified:
    ; dw 0xFFFF, 0
    ; db 0, 0x9A, 0xAF, 0 (This is usually for 64-bit code)
    ; My previous thought:
    ; dw 0
    ; dw 0
    ; db 0
    ; db 10011010b (Access)
    ; db 00100000b (Flags=0x20, Limit=0)
    ; db 0
    
gdt_data:
    dq 0x0000920000000000 ; Data 64-bit
    ; Access: 10010010b = 0x92 (Present, Ring 0, Data, RW)
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dq gdt_start

; Padding to 510
times 510-($-$$) db 0
dw 0xAA55
