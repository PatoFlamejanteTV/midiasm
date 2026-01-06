#!/usr/bin/env python3
import struct
import sys

def read_variable_length(data, pointer):
    """
    Reads a MIDI variable length quantity.
    Returns (value, new_pointer).
    """
    value = 0
    if pointer >= len(data):
        return 0, pointer
        
    while True:
        if pointer >= len(data): break
        byte = data[pointer]
        pointer += 1
        value = (value << 7) | (byte & 0x7F)
        if not (byte & 0x80):
            break
    return value, pointer

def midi_to_bin(input_file, output_file):
    print(f"Processing {input_file}...")
    
    with open(input_file, 'rb') as f:
        data = f.read()

    if data[0:4] != b'MThd':
        print("Error: Invalid MIDI header")
        return

    # Parse Header
    fmt, tracks, division = struct.unpack('>HHH', data[8:14])
    print(f"Format: {fmt}, Tracks: {tracks}, Division: {division}")
    
    # Extract ticks per beat (assuming bit 15 is 0)
    ticks_per_beat = division
    if division & 0x8000:
        print("Warning: SMPTE time code not fully supported, assuming 120BPM default math.")
        ticks_per_beat = 480 # Fallback

    # --- Step 1: Parse all events from all tracks ---
    all_events = []
    
    pointer = 14
    for i in range(tracks):
        # Find MTrk chunk
        while pointer < len(data):
            if data[pointer:pointer+4] == b'MTrk':
                length = struct.unpack('>I', data[pointer+4:pointer+8])[0]
                chunk_start = pointer + 8
                chunk_end = chunk_start + length
                
                # Parse Track
                p = chunk_start
                curr_ticks = 0
                last_status = 0
                
                while p < chunk_end:
                    delta, p = read_variable_length(data, p)
                    curr_ticks += delta
                    
                    if p >= chunk_end: break
                    
                    byte = data[p]
                    if byte & 0x80:
                        status = byte
                        p += 1
                        last_status = status
                    else:
                        status = last_status
                    
                    cmd = status & 0xF0
                    
                    # Store event
                    # We only really care about Note On/Off and Tempo
                    event_data = []
                    
                    if cmd in [0x80, 0x90, 0xA0, 0xB0, 0xE0]:
                        event_data = data[p:p+2]
                        p += 2
                    elif cmd in [0xC0, 0xD0]:
                        event_data = data[p:p+1]
                        p += 1
                    elif cmd == 0xF0:
                        if status == 0xFF: # Meta
                            meta_type = data[p]
                            p += 1
                            l, p = read_variable_length(data, p)
                            meta_content = data[p:p+l]
                            p += l
                            
                            # Handle Tempo immediately or store it? 
                            # Storing all and sorting is better.
                            all_events.append({
                                'tick': curr_ticks,
                                'type': 'meta',
                                'meta_type': meta_type,
                                'data': meta_content
                            })
                            continue
                        else: # Sysex
                            l, p = read_variable_length(data, p)
                            p += l
                            continue
                    
                    # Add Note/Music Event
                    if cmd in [0x80, 0x90]:
                        all_events.append({
                            'tick': curr_ticks,
                            'type': 'midi',
                            'cmd': cmd,
                            'note': event_data[0],
                            'vel': event_data[1]
                        })
                
                pointer = chunk_end
                break
            else:
                # Skip unknown chunk (header has length)
                # But standardized MIDI usually has MTrk right after. 
                # If we are lost, scan forward byte by byte? No, risky. 
                # Assuming valid MIDI structure for now.
                pointer += 1

    # --- Step 2: Merge and Sort ---
    # Sort by time
    all_events.sort(key=lambda x: x['tick'])
    
    # --- Step 3: Normalize to Audio Stream (Highest Note Priority) ---
    output_stream = [] # (duration_ms, divisor)
    
    current_tempo = 500000 # Default 120 BPM (us/beat)
    current_tick = 0
    active_notes = set() # Set of active MIDI note numbers
    
    # To accumulate small segments
    accumulated_duration = 0.0
    
    for event in all_events:
        delta_ticks = event['tick'] - current_tick
        
        if delta_ticks > 0:
            # Time passed -> Emit sound state
            # Calculate duration in ms
            duration_ms = (delta_ticks * current_tempo / ticks_per_beat) / 1000.0
            
            # Decide Frequency
            divisor = 0
            if active_notes:
                # Highest note priority
                highest = max(active_notes)
                # Freq = 440 * 2^((note-69)/12)
                # Divisor = 1193180 / Freq
                freq = 440.0 * (2.0 ** ((highest - 69) / 12.0))
                divisor = int(1193180 / freq)
            
            # Optimization: Merge with previous if same divisor
            if output_stream and output_stream[-1][1] == divisor:
                output_stream[-1] = (output_stream[-1][0] + duration_ms, divisor)
            else:
                output_stream.append((duration_ms, divisor))
                
            current_tick = event['tick']
            
        # Process Event State
        if event['type'] == 'meta' and event['meta_type'] == 0x51:
            # Tempo Change
            d = event['data']
            if len(d) >= 3:
                current_tempo = (d[0] << 16) | (d[1] << 8) | d[2]
                
        elif event['type'] == 'midi':
            cmd = event['cmd']
            note = event['note']
            vel = event['vel']
            
            if cmd == 0x90 and vel > 0:
                active_notes.add(note)
            elif cmd == 0x80 or (cmd == 0x90 and vel == 0):
                active_notes.discard(note)

    # --- Step 4: Write Binary ---
    print(f"Writing {len(output_stream)} frequency segments to {output_file}...")
    
    with open(output_file, 'wb') as f:
        count = 0
        for duration_float, divisor in output_stream:
            # Round duration
            duration = int(round(duration_float))
            
            if duration <= 0: continue
            
            # Split if > 65535 (uint16 max)
            while duration > 65535:
                f.write(struct.pack('<HH', 65535, divisor))
                duration -= 65535
            
            f.write(struct.pack('<HH', duration, divisor))
            count += 1
            
        # End Marker
        f.write(struct.pack('<HH', 0, 0))
        
    print(f"Done! Written {count} machine words.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 smart_converter.py <input.mid> <output.bin>")
        print("Example: python3 smart_converter.py song.mid music.bin")
    else:
        midi_to_bin(sys.argv[1], sys.argv[2])
