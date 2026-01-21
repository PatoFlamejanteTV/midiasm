#!/usr/bin/env python3
import struct

def write_varlen(val):
    if val == 0:
        return b'\x00'
    chunks = []
    while val > 0:
        chunks.append(val & 0x7F)
        val >>= 7
    chunks.reverse()
    out = []
    for i in range(len(chunks) - 1):
        out.append(chunks[i] | 0x80)
    out.append(chunks[-1])
    return bytes(out)

def create_multi_layer_midi(filename):
    # Header: MThd, length 6, format 1 (Multi-track), 2 tracks, 480 ticks/beat
    header = b'MThd' + struct.pack('>IHHH', 6, 1, 2, 480)
    
    # Track 1: Bass Line (C3, G3, C3, G3)
    # Quarter notes (480 ticks)
    events1 = b''
    notes1 = [48, 55, 48, 55] 
    for note in notes1:
        events1 += b'\x00' + bytes([0x90, note, 0x7F]) # Note On
        events1 += write_varlen(480) + bytes([0x80, note, 0x00]) # Note Off
    events1 += b'\x00\xFF\x2F\x00'
    track1 = b'MTrk' + struct.pack('>I', len(events1)) + events1
    
    # Track 2: Melody (E4, F4, G4...)
    # Eighth notes (240 ticks)
    events2 = b''
    # Start slightly later to test overlap
    events2 += write_varlen(240) # Wait 240
    notes2 = [64, 65, 67, 69, 71, 72]
    for note in notes2:
         events2 += b'\x00' + bytes([0x90, note, 0x7F])
         events2 += write_varlen(240) + bytes([0x80, note, 0x00])
    events2 += b'\x00\xFF\x2F\x00'
    track2 = b'MTrk' + struct.pack('>I', len(events2)) + events2

    with open(filename, 'wb') as f:
        f.write(header + track1 + track2)

if __name__ == '__main__':
    create_multi_layer_midi('multi_layer_test.mid')
