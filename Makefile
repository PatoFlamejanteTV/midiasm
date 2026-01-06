all: os.img

os.img: boot.bin kernel.bin
	cat boot.bin kernel.bin > os.img
	truncate -s 1440k os.img

boot.bin: boot.asm
	nasm -f bin boot.asm -o boot.bin

kernel.bin: kernel.asm sonic.bin
	nasm -f bin kernel.asm -o kernel.bin

sonic.bin: scd-Palmtree_Panic_Past.mid smart_converter.py
	python3 smart_converter.py scd-Palmtree_Panic_Past.mid sonic.bin

clean:
	rm -f *.bin os.img
