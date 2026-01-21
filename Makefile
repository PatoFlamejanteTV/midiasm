all: os.img uefi.img

os.img: boot.bin kernel.bin
	cat boot.bin kernel.bin > os.img
	truncate -s 1440k os.img

boot.bin: boot.asm
	nasm -f bin boot.asm -o boot.bin

bg.bin: res/sample.bmp compress_bg.py
	python3 compress_bg.py res/sample.bmp

kernel.bin: kernel.asm sonic.bin bg.bin
	nasm -f bin kernel.asm -o kernel.bin

sonic.bin: scd-Palmtree_Panic_Past.mid smart_converter.py
	python3 smart_converter.py scd-Palmtree_Panic_Past.mid sonic.bin

qemu:
	qemu-system-x86_64 -drive format=raw,file=os.img -audiodev pa,id=snd0 -machine pcspk-audiodev=snd0


uefi.bin: uefi.asm sonic.bin
	nasm -f bin uefi.asm -o uefi.bin

uefi.img: uefi.bin
	dd if=/dev/zero of=uefi.img bs=1M count=64
	mformat -i uefi.img -F ::
	mmd -i uefi.img ::/EFI
	mmd -i uefi.img ::/EFI/BOOT
	mcopy -i uefi.img uefi.bin ::/EFI/BOOT/BOOTX64.EFI

run-uefi: uefi.img
	qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -drive format=raw,file=uefi.img

clean:
	rm -f *.bin os.img uefi.img

