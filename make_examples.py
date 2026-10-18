#!/usr/bin/env python3
"""Generate the example media (example.png, example.mp4) at install time.

The repo ships no binaries, so the Pi App Store can review everything.
Both samples are original synthetic landscapes, deterministic, stdlib-only
for the PNG; the MP4 needs ffmpeg (already required by cview itself).
"""
import os, struct, subprocess, sys, zlib

W, H = 320, 180


def sky(x, y):
    """One pixel of a simple synthetic landscape."""
    horizon = H * 2 // 3
    if y < horizon:
        t = y / horizon
        r = int(30 + 60 * t)
        g = int(60 + 80 * t)
        b = int(140 + 60 * t)
        # sun
        if (x - 240) ** 2 + (y - 45) ** 2 < 18 ** 2:
            r, g, b = 255, 230, 140
    else:
        t = (y - horizon) / (H - horizon)
        # rolling hills via two sine ridges
        ridge = horizon + 14 * (1 + 0.5 * (1 + __import__('math').sin(x / 37.0)))
        if y < ridge:
            r, g, b = 40, int(110 - 40 * t), 50
        else:
            r, g, b = 30, int(70 - 20 * t), 35
    return r, g, b


def write_png(path, shift=0):
    def chunk(tag, data):
        c = tag + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c))
    raw = b''
    for y in range(H):
        raw += b'\x00' + b''.join(bytes(sky((x + shift) % W, y)) for x in range(W))
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    png = os.path.join(here, 'example.png')
    write_png(png)
    print('wrote example.png')
    ff = None
    for name in ('ffmpeg',):
        for d in os.environ.get('PATH', '').split(os.pathsep):
            p = os.path.join(d, name)
            if os.path.isfile(p) and os.access(p, os.X_OK):
                ff = p
    if not ff:
        print('ffmpeg not found; skipping example.mp4 (cview needs ffmpeg anyway)')
        return 0
    tmp = os.path.join(here, '.example-frames')
    os.makedirs(tmp, exist_ok=True)
    try:
        for i in range(96):  # 4 seconds at 24fps, slow pan
            write_png(os.path.join(tmp, 'f%03d.png' % i), shift=i)
        subprocess.run([ff, '-y', '-loglevel', 'error', '-framerate', '24',
                        '-i', os.path.join(tmp, 'f%03d.png'),
                        '-pix_fmt', 'yuv420p', os.path.join(here, 'example.mp4')],
                       check=True)
        print('wrote example.mp4')
    finally:
        for f in os.listdir(tmp):
            os.unlink(os.path.join(tmp, f))
        os.rmdir(tmp)
    return 0


if __name__ == '__main__':
    sys.exit(main())
