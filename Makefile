all: os.img

os.img: boot.bin music.bin
	cat boot.bin music.bin > os.img
	truncate -s 1440k os.img

boot.bin: boot.asm
	nasm -f bin boot.asm -o boot.bin

music.bin: test.mid
	python3 midi2bin.py test.mid music.bin

test.mid: generate_song.py
	python3 generate_song.py

run: os.img
	qemu-system-x86_64 -drive format=raw,file=os.img -audiodev pa,id=snd0 -machine pcspk-audiodev=snd0

clean:
	rm -f *.bin *.img *.mid
