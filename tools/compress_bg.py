#!/usr/bin/env python3
import sys
#import struct
from PIL import Image

# VGA Default Palette (Colors 0-7)
PALETTE = [
    (0, 0, 0),       # 0: Black
    (0, 0, 170),     # 1: Blue
    (0, 170, 0),     # 2: Green
    (0, 170, 170),   # 3: Cyan
    (170, 0, 0),     # 4: Red
    (170, 0, 170),   # 5: Magenta
    (170, 85, 0),    # 6: Brown
    (170, 170, 170)  # 7: Light Grey
]

def closest_color(rgb):
    min_dist = float('inf')
    best_idx = 0
    r, g, b = rgb
    for i, (pr, pg, pb) in enumerate(PALETTE):
        dist = (r - pr)**2 + (g - pg)**2 + (b - pb)**2
        if dist < min_dist:
            min_dist = dist
            best_idx = i
    return best_idx

def compress_image(image_path, output_bin, output_preview):
    try:
        img = Image.open(image_path)
    except Exception as e:
        print(f"Error opening image: {e}")
        sys.exit(1)

    # Resize to 80x25
    img = img.resize((80, 25), Image.Resampling.NEAREST) #TODO: Make it better and actually understandable
    img = img.convert('RGB')
    
    pixels = list(img.getdata())
    
    # Map to 0-7
    mapped_pixels = [closest_color(p) for p in pixels]
    
    # RLE Compression
    # Format: [Count, Color] per run.
    # Count is 1 byte (max 255). Color is 1 byte (0-7).
    
    rle_data = []
    if not mapped_pixels:
        return

    current_color = mapped_pixels[0]
    count = 1
    
    for color in mapped_pixels[1:]:
        if color == current_color and count < 255:
            count += 1
        else:
            rle_data.append(count)
            rle_data.append(current_color)
            current_color = color
            count = 1
    
    # Append last run
    rle_data.append(count)
    rle_data.append(current_color)
    
    # Write Binary
    with open(output_bin, 'wb') as f:
        f.write(bytes(rle_data))
        # Add 0,0 terminator just in case, though we know 80x25=2000 pixels
        f.write(bytes([0, 0]))
    
    print(f"Compressed size: {len(rle_data)} bytes")
    
    # Reconstruct for Preview
    preview_img = Image.new('RGB', (80, 25))
    recon_pixels = []
    
    # Decode RLE
    i = 0
    while i < len(rle_data):
        cnt = rle_data[i]
        col = rle_data[i+1]
        rgb = PALETTE[col]
        recon_pixels.extend([rgb] * cnt)
        i += 2
        
    preview_img.putdata(recon_pixels)
    preview_img = preview_img.resize((800, 250), Image.Resampling.NEAREST) # Upscale for easier viewing
    preview_img.save(output_preview)
    print(f"Saved preview: {output_preview}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: compress_bg.py <input.bmp>")
        sys.exit(1)
        
    compress_image(sys.argv[1], "bg.bin", "preview_bg.png")
