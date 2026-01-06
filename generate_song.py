import struct

def write_varlen(val):
    if val == 0:
        return b'\x00'
    chunks = []
    while val > 0:
        chunks.append(val & 0x7F)
        val >>= 7
    # Chunks are LSB...MSB
    # We want MSB...LSB in file
    # MSB...Mid have bit 7 set. LSB has bit 7 clear.
    chunks.reverse() # Now MSB...LSB
    out = []
    for i in range(len(chunks) - 1):
        out.append(chunks[i] | 0x80)
    out.append(chunks[-1])
    return bytes(out)

def create_midi(filename):
    # Header: MThd, length 6, format 0, 1 track, 480 ticks/beat
    header = b'MThd' + struct.pack('>IHHH', 6, 0, 1, 480)
    
    events = b''
    
    # Simple melody: C Major scale up and down
    # Notes: C4(60), D4(62), E4(64), F4(65), G4(67), A4(69), B4(71), C5(72)
    notes = [60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60]
    duration = 240 # ticks (eighth note)
    
    t = 0
    
    # Set Tempo (optional, defaults to 120bpm -> 500ms/beat)
    # Meta 0x51 len 3 -> 500,000 us (07 A1 20)
    events += b'\x00\xFF\x51\x03\x07\xA1\x20' 
    
    for note in notes:
        # Note On: Delta 0, 90 note 7F
        events += b'\x00' + bytes([0x90, note, 0x7F])
        
        # Note Off: Delta duration, 80 note 00
        events += write_varlen(duration) + bytes([0x80, note, 0x00])
        
    # End of Track
    events += b'\x00\xFF\x2F\x00'
    
    # Track Chunk
    track = b'MTrk' + struct.pack('>I', len(events)) + events
    
    with open(filename, 'wb') as f:
        f.write(header + track)

if __name__ == '__main__':
    create_midi('test.mid')
