[BITS 16]
[ORG 0x7C00]

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; Load Kernel + Music from disk to 0x8000
    ; We'll read 128 sectors (64KB) to be safe.
    ; This covers the kernel (~1KB) and the music (~4KB)
    mov ah, 0x02    ; Read sectors
    mov al, 128     ; Count
    mov ch, 0       ; Cyl
    mov cl, 2       ; Sec (Start from 2)
    mov dh, 0       ; Head
    mov bx, 0x8000  ; Dest
    int 0x13
    
    ; Jump to Kernel
    jmp 0x0000:0x8000

times 510-($-$$) db 0
dw 0xAA55
