all: os.img uefi.img

os.img: boot.bin kernel.bin
	cat boot.bin kernel.bin > os.img
	truncate -s 1440k os.img

boot.bin: asm/boot.asm
	nasm -f bin asm/boot.asm -o boot.bin

bg.bin: res/img/sample.bmp tools/compress_bg.py
	python3 tools/compress_bg.py res/img/ba.jpg

kernel.bin: asm/kernel.asm ba.bin $(if $(NO_BG),,bg.bin)
	nasm -f bin -I ./ $(if $(NOISE),-DNOISE_BUILD,) $(if $(NO_BG),-DNO_BG,) asm/kernel.asm -o kernel.bin

sonic.bin: res/midi/scd-Palmtree_Panic_Past.mid tools/smart_converter.py
	python3 tools/smart_converter.py res/midi/scd-Palmtree_Panic_Past.mid sonic.bin

ba.bin: res/midi/badapple.mid tools/smart_converter.py
	python3 tools/smart_converter.py res/midi/badapple.mid ba.bin

qemu:
	qemu-system-x86_64 -drive format=raw,file=os.img -audiodev pa,id=snd0 -machine pcspk-audiodev=snd0


uefi.bin: asm/uefi.asm ba.bin
	nasm -f bin -I ./ asm/uefi.asm -o uefi.bin

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

