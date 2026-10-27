#!/usr/bin/env python3
"""Development-only conversion of the official MARSTEK square mark to ICNS.

Requires Pillow. The app/build uses the committed ICNS;
neither this script nor Python is shipped as a runtime dependency.
"""
from pathlib import Path
from io import BytesIO
import struct

from PIL import Image, ImageDraw, ImageFilter


def main():
    directory = Path(__file__).resolve().parent
    source = Image.open(directory / "marstek-official-app-logo.jpg").convert("RGBA")
    if source.size != (1000, 1000):
        raise ValueError("The inspected official source must remain 1000 × 1000.")

    # Keep the manufacturer's square artwork intact inside a macOS-sized tile.
    canvas = Image.new("RGBA", (1024, 1024))
    tile = source.resize((860, 860), Image.Resampling.LANCZOS)
    mask = Image.new("L", tile.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 859, 859), radius=184, fill=255)
    shadow = Image.new("RGBA", canvas.size)
    shadow_mask = Image.new("L", canvas.size)
    ImageDraw.Draw(shadow_mask).rounded_rectangle((82, 90, 941, 949), radius=184, fill=82)
    shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(13)))
    canvas.alpha_composite(shadow)
    tile.putalpha(mask)
    canvas.alpha_composite(tile, (82, 82))
    canvas.save(directory / "VenusBar-1024.png", optimize=True)

    # Modern ICNS PNG representations, including native 16/32 and Retina sizes.
    types = {b"icp4": 16, b"icp5": 32, b"icp6": 64, b"ic07": 128,
             b"ic08": 256, b"ic09": 512, b"ic10": 1024, b"ic11": 32,
             b"ic12": 64, b"ic13": 256, b"ic14": 512}
    pngs = {}
    for size in set(types.values()):
        stream = BytesIO()
        canvas.resize((size, size), Image.Resampling.LANCZOS).save(stream, "PNG", optimize=True)
        pngs[size] = stream.getvalue()
    entries = [(kind, pngs[size]) for kind, size in types.items()]
    toc = b"".join(kind + struct.pack(">I", len(data) + 8) for kind, data in entries)
    body = b"TOC " + struct.pack(">I", len(toc) + 8) + toc
    body += b"".join(kind + struct.pack(">I", len(data) + 8) + data for kind, data in entries)
    (directory / "VenusBar.icns").write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    main()
