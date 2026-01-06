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
    ; Load 127 sectors (approx 64KB) - Max readable in one go usually, 
    ; but to be safe we'll read as much as we likely need or loop.
    ; For a simple bootloader, we'll read 128 sectors (64KB) just to be safe.
    ; Actually, let's read 120 sectors to stay within safe range of single read call on some BIOSes,
    ; or just do a loop if needed. For simplicity, just read 64 sectors (32KB) initially,
    ; but the sonic song might be larger.
    ; scd-Palmtree_Panic_Past.mid converted is 3416 bytes in sonic.bin? 
    ; Wait, Step 106 says "Writing 853 frequency segments to sonic.bin...".
    ; 853 * 4 bytes = 3412 bytes. 3KB. 64 sectors (32KB) is plenty.
    
    mov ah, 0x02    ; Read sectors
    mov al, 64      ; Count (32KB)
    mov ch, 0       ; Cyl
    mov cl, 2       ; Sec
    mov dh, 0       ; Head
    mov bx, 0x8000  ; Dest
    int 0x13

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

    ; Enable Paging
    mov eax, cr0
    or eax, 1 << 31
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

    mov rsi, 0x8000

play_loop:
    xor rax, rax
    lodsw           ; Duration (low 16)
    mov rbx, rax
    
    lodsw           ; Divisor (high 16 -> wait, format is Dur, Div)
    mov rcx, rax
    
    test rbx, rbx
    jnz .check_play
    test rcx, rcx
    jz hang
    
.check_play:
    test rcx, rcx
    jz .silence
    
    ; Play
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

delay_ms:
    test rdi, rdi
    jz .done
.ms_loop:
    push rdi
    mov rdi, 1193 ; ~1ms
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
    dq 0x00209A0000000000 ; Code 64: Present, Ring0, Exec/Read
gdt_data:
    dq 0x0000920000000000 ; Data 64: Present, Ring0, RW
gdt_end:
gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dq gdt_start

times 510-($-$$) db 0
dw 0xAA55
