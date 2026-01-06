#!/usr/bin/env python3
import struct
import sys
import math

def read_variable_length(data, pointer):
    value = 0
    while True:
        byte = data[pointer]
        pointer += 1
        value = (value << 7) | (byte & 0x7F)
        if not (byte & 0x80):
            break
    return value, pointer

def parse_midi_to_bin(midi_path, output_path):
    with open(midi_path, 'rb') as f:
        data = f.read()

    if data[0:4] != b'MThd':
        print("Invalid MIDI header")
        return

    # Header parameters
    fmt, tracks, division = struct.unpack('>HHH', data[8:14])
    # division: if top bit 0, ticks per quarter note.
    
    print(f"Format: {fmt}, Tracks: {tracks}, Division: {division}")

    # Find the track with notes (simplified scanning)
    pointer = 14
    track_data = None
    
    for i in range(tracks):
        if data[pointer:pointer+4] != b'MTrk':
            print("Expected MTrk")
            break
        length = struct.unpack('>I', data[pointer+4:pointer+8])[0]
        pointer += 8
        chunk = data[pointer:pointer+length]
        
        # Heuristic: Check for Note On events (0x9n)
        has_notes = False
        for j in range(len(chunk)-3):
            if (chunk[j] & 0xF0) == 0x90:
                has_notes = True
                break
        
        if has_notes:
            track_data = chunk
            print(f"Selected Track {i+1} (Length: {length})")
            break
            
        pointer += length

    if not track_data:
        print("No track with notes found")
        # Fallback to first track if single track
        if tracks == 1:
             pointer = 14 + 8 # Skip MThd and MTrk header
             length = struct.unpack('>I', data[18:22])[0]
             track_data = data[22:22+length]
        else:
            return

    # Parse Events
    events = [] # (time_ms, note_freq_divisor)
    
    # Tempo defaults to 500000 microseconds per beat (120 BPM)
    tempo = 500000 
    
    current_tick = 0
    p = 0
    last_status = 0
    
    # State
    active_note = 0
    
    output_events = [] # (duration_ms, divisor)

    ticks_per_beat = division # Assuming top bit is 0 for simplicity
    
    abs_time_us = 0
    last_event_time_us = 0

    while p < len(track_data):
        delta_ticks, p = read_variable_length(track_data, p)
        
        # Calculate time delta in microseconds
        delta_us = (delta_ticks * tempo) / ticks_per_beat
        abs_time_us += delta_us
        
        duration_since_last = (abs_time_us - last_event_time_us) / 1000.0
        
        # print(f"Delta: {delta_ticks} ticks, {duration_since_last}ms. Active: {active_note}")

        if delta_ticks > 0:
            divisor = 0
            if active_note > 0:
                freq = 440.0 * (2.0 ** ((active_note - 69) / 12.0))
                divisor = int(1193180 / freq)
            
            if duration_since_last > 1:
                 # print(f"Adding event: {duration_since_last}ms, Div: {divisor}")
                 if output_events and output_events[-1][1] == divisor:
                     output_events[-1] = (output_events[-1][0] + int(duration_since_last), divisor)
                 else:
                     output_events.append((int(duration_since_last), divisor))
            
            last_event_time_us = abs_time_us

        if p >= len(track_data): break
        
        byte = track_data[p]
        # print(f"Byte at {p}: {hex(byte)}")

        if byte & 0x80:
            status = byte
            p += 1
            last_status = status
        else:
            status = last_status
            
        cmd = status & 0xF0
        
        if cmd == 0x80: # Note Off
            note = track_data[p]
            vel = track_data[p+1]
            p += 2
            if note == active_note:
                active_note = 0
                
        elif cmd == 0x90: # Note On
            note = track_data[p]
            vel = track_data[p+1]
            p += 2
            if vel == 0: # Note On with vel 0 is Note Off
                if note == active_note:
                    active_note = 0
            else:
                active_note = note
                
        elif cmd == 0xC0: # Program Change
            p += 1
        elif cmd == 0xD0: # Channel Aftertouch
            p += 1
        elif cmd == 0xF0: # Sysex or Meta
            if status == 0xFF: # Meta
                meta_type = track_data[p]
                p += 1
                length, p = read_variable_length(track_data, p)
                
                if meta_type == 0x51: # Set Tempo
                    # 3 bytes big endian
                    t1, t2, t3 = track_data[p], track_data[p+1], track_data[p+2]
                    tempo = (t1 << 16) | (t2 << 8) | t3
                    # print(f"Tempo Check: {tempo} us/beat")
                
                p += length
            else:
                 # Normal ticks... handle sysex length?
                 # Simplified: Assume F0/F7 have length
                 length, p = read_variable_length(track_data, p)
                 p += length
        else:
            # 3 byte cmds: NoteOff, NoteOn, KeyPressure, ControlChange, PitchBend
            # 2 byte cmds: ProgChange, ChanPressure
            if cmd in [0x80, 0x90, 0xA0, 0xB0, 0xE0]:
                p += 2
            elif cmd in [0xC0, 0xD0]:
                p += 1
                
    # Write binary
    with open(output_path, 'wb') as f:
        print(f"Writing {len(output_events)} events...")
        for duration, divisor in output_events:
            # Limit duration to 65535ms to fit in word, split if needed
            while duration > 65535:
                f.write(struct.pack('<HH', 65535, divisor))
                duration -= 65535
            f.write(struct.pack('<HH', int(duration), divisor))
        
        # End marker
        f.write(struct.pack('<HH', 0, 0))

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: midi2bin.py <input.mid> <output.bin>")
    else:
        parse_midi_to_bin(sys.argv[1], sys.argv[2])
