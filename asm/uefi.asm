[BITS 64]
[ORG 0x00400000]
default rel

IMAGE_BASE         equ 0x00400000
SECTION_ALIGNMENT  equ 4096
FILE_ALIGNMENT     equ 512

; PE header
header:
    dw "MZ"
    dw 0
    dd "PE"
    dw 0x8664       ; Machine (x64)
    dw 2            ; NumberOfSections
    dd 0            ; TimeDateStamp
    dd 0            ; PointerToSymbolTable
    dd 0            ; NumberOfSymbols
    dw 140          ; SizeOfOptionalHeader
    dw 0x2022       ; Characteristics (Executable | LargeAddressAware | DLL)
    dw 0x20b        ; Magic (PE32+)
    db 0            ; MajorLinkerVersion
    db 0            ; MinorLinkerVersion
    dd text_size    ; SizeOfCode
    dd data_size    ; SizeOfInitializedData
    dd 0            ; SizeOfUninitializedData
    dd entry_point - IMAGE_BASE ; AddressOfEntryPoint (RVA)
    dd 4096         ; BaseOfCode (RVA of .text seems safest as 4096)
    dq IMAGE_BASE   ; ImageBase
    dd SECTION_ALIGNMENT ; SectionAlignment
    dd FILE_ALIGNMENT    ; FileAlignment
    dw 4            ; MajorOperatingSystemVersion
    dw 0            ; MinorOperatingSystemVersion
    dw 0            ; MajorImageVersion
    dw 0            ; MinorImageVersion
    dw 4            ; MajorSubsystemVersion
    dw 0            ; MinorSubsystemVersion
    dd 0            ; Win32VersionValue
    dd image_size   ; SizeOfImage (Aligned)
    dd 4096         ; SizeOfHeaders (Aligned to SectionAlignment to match offset)
    dd 0            ; CheckSum
    dw 10           ; Subsystem (EFI Application)
    dw 0            ; DllCharacteristics
    dq 0x100000     ; SizeOfStackReserve
    dq 0x1000       ; SizeOfStackCommit
    dq 0x100000     ; SizeOfHeapReserve
    dq 0x1000       ; SizeOfHeapCommit
    dd 0            ; LoaderFlags
    dd 16           ; NumberOfRvaAndSizes
    times 128 db 0  ; Data Directories (Empty)

; Sections
; .text
dq ".text"
    dd text_size                ; VirtualSize
    dd text_start - IMAGE_BASE  ; VirtualAddress (RVA)
    dd text_size                ; SizeOfRawData
    dd text_start - IMAGE_BASE  ; PointerToRawData (File Offset)
    dd 0, 0
    dw 0, 0
    dd 0x60000020   ; Characteristics (Code | Execute | Read)

; .data
dq ".data"
    dd data_size                ; VirtualSize
    dd data_start - IMAGE_BASE  ; VirtualAddress (RVA)
    dd data_size                ; SizeOfRawData
    dd data_start - IMAGE_BASE  ; PointerToRawData (File Offset)
    dd 0, 0
    dw 0, 0
    dd 0xC0000040   ; Characteristics (Initialized Data | Read | Write)

align SECTION_ALIGNMENT
text_start:
entry_point:
    sub rsp, 120 ; Shadow(32) + Args(8*10) - Align 16

    mov [ImageHandle], rcx
    mov [SystemTable], rdx

    ; Get BootServices (Offset 96)
    mov rax, [rdx + 96]
    mov [BootServices], rax

    ; Locate GOP
    lea rcx, [EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID]
    xor rdx, rdx
    lea r8, [Gop]
    mov rax, [BootServices]
    call [rax + 320] ; LocateProtocol

    test rax, rax
    jnz hang

    ; Get Screen Info
    mov rcx, [Gop]
    mov rax, [rcx + 24] ; Mode
    mov ebx, [rax + 32] ; FrameBufferSize
    mov [FrameBufferSize], ebx
    mov rax, [rax + 8]  ; Info
    mov ebx, [rax + 4]  ; Width
    mov [ScreenWidth], ebx
    mov ebx, [rax + 8]  ; Height
    mov [ScreenHeight], ebx

    ; Calculate Column Width: (ScreenWidth / 80)
    xor rdx, rdx
    mov eax, ebx
    mov ecx, 80
    div ecx
    mov [ColWidth], eax

    ; Main Loop
    lea rsi, [music_data] ; Use LEA for PIC

next_note:
    xor rax, rax
    lodsw
    mov r8, rax ; Dur
    lodsw
    mov r9, rax ; Div
    lodsw
    mov r10, rax ; Chan

    mov rax, r8
    or rax, r9
    or rax, r10
    jz hang

    ; Visualizer
    call uefi_vis_update

    ; Sound
    cmp r9, 0
    je .silence
    
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
    jmp .wait

.silence:
    in al, 0x61
    and al, 0xFC
    out 0x61, al

.wait:
    ; Stall (microseconds)
    mov rax, r8
    imul rax, 1000
    mov rcx, rax
    mov rax, [BootServices]
    call [rax + 248] ; Stall

    jmp next_note

hang:
    in al, 0x61
    and al, 0xFC
    out 0x61, al
.loop:
    hlt
    jmp .loop

; Subroutines
uefi_vis_update:
    ; Scroll Screen (Blt VideoToVideo)
    ; Src: (0, 16) -> Dst: (0, 0), w=Width, h=Height-16
    mov rax, [ScreenHeight]
    sub rax, 16
    cmp rax, 0
    jle .draw_note ; Safety

    mov rcx, [Gop]
    xor rdx, rdx   ; BltBuffer (Optional)
    mov r8, 2      ; EfiBltVideoToVideo
    xor r9, r9     ; SrcX = 0
    
    mov qword [rsp+32], 16   ; SrcY
    mov qword [rsp+40], 0    ; DstX
    mov qword [rsp+48], 0    ; DstY
    mov rax, [ScreenWidth]
    mov [rsp+56], rax        ; Width
    mov rax, [ScreenHeight]
    sub rax, 16
    mov [rsp+64], rax        ; Height
    mov qword [rsp+72], 0    ; Delta

    mov rax, [Gop]
    call [rax + 16] ; Blt

    ; Clear Bottom Line (Dst: 0, H-16, W, 16) -> Black
    mov rcx, [Gop]
    lea rdx, [BlackPixel]    ; BltBuffer (Pixel)
    mov r8, 0                ; EfiBltVideoFill
    xor r9, r9               ; SrcX
    
    mov qword [rsp+32], 0    ; SrcY
    mov qword [rsp+40], 0    ; DstX
    mov rax, [ScreenHeight]
    sub rax, 16
    mov [rsp+48], rax        ; DstY
    mov rax, [ScreenWidth]
    mov [rsp+56], rax        ; Width
    mov qword [rsp+64], 16   ; Height
    mov qword [rsp+72], 0    ; Delta

    mov rax, [Gop]
    call [rax + 16] ; Blt

.draw_note:
    ; Draw Note
    cmp r9, 0 ; Div == 0?
    je .ret

    ; Calculate Pos (0-79)
    mov rax, r9
    shr rax, 7
    mov rbx, 79
    sub rbx, rax
    cmp rbx, 0
    jge .c1
    mov rbx, 0
.c1:
    cmp rbx, 79
    jle .c2
    mov rbx, 79
.c2:
    
    ; Convert to Pixels X
    mov rax, rbx
    mov ecx, [ColWidth]
    mul ecx
    mov rbx, rax ; X pos

    ; Color
    lea rdx, [WhitePixel] ; Default
    and r10, 0xF
    inc r10
    cmp r10, 1
    je .blue
    cmp r10, 2
    je .green
    cmp r10, 3
    je .cyan
    cmp r10, 4
    je .red
    cmp r10, 5
    je .purple
    jmp .do_draw
.blue:
    lea rdx, [BluePixel]
    jmp .do_draw
.green:
    lea rdx, [GreenPixel]
    jmp .do_draw
.cyan:
    lea rdx, [CyanPixel]
    jmp .do_draw
.red:
    lea rdx, [RedPixel]
    jmp .do_draw
.purple:
    lea rdx, [PurplePixel]
.do_draw:

    ; Blt Fill Note
    mov rcx, [Gop]
    ; rdx is Pixel
    mov r8, 0 ; Fill
    xor r9, r9
    
    mov qword [rsp+32], 0
    mov [rsp+40], rbx      ; DstX
    mov rax, [ScreenHeight]
    sub rax, 16
    mov [rsp+48], rax      ; DstY
    mov rax, [ColWidth]
    mov [rsp+56], rax      ; Width
    mov qword [rsp+64], 16 ; Height
    mov qword [rsp+72], 0

    mov rax, [Gop]
    call [rax + 16]

.ret:
    ret

align SECTION_ALIGNMENT
text_size equ $ - text_start

data_start:
EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID:
    dd 0x9042a9de
    dw 0x23dc
    dw 0x4a38
    db 0x96, 0xfb, 0x7a, 0xde, 0xd0, 0x80, 0x51, 0x6a

Gop dq 0
ImageHandle dq 0
SystemTable dq 0
BootServices dq 0
FrameBuffer dq 0
FrameBufferSize dq 0
ScreenWidth dq 800
ScreenHeight dq 600
ColWidth dq 10

; Colors (0x00RRGGBB)
align 4
BlackPixel dd 0x00000000
WhitePixel dd 0x00FFFFFF
BluePixel  dd 0x000000FF
GreenPixel dd 0x0000FF00
CyanPixel  dd 0x0000FFFF
RedPixel   dd 0x00FF0000
PurplePixel dd 0x00FF00FF

align 16
music_data:
    incbin "ba.bin"
    times 16 db 0

align SECTION_ALIGNMENT
data_size equ $ - data_start

image_size equ $ - header
