#!/usr/bin/env python3
# cview.py - show PNG/JPG images and MP4 videos in the terminal as colored half-blocks.
# Needs only python3 and ffmpeg (ffprobe comes with it).
# Usage: python3 cview.py FILE [cols] [-fps N] [-256]
# Images print once. Videos are converted to a cache file first (FILE.cols.ubv), then played at the right speed.
import sys, os, subprocess, shutil, struct, zlib, time, json

def die(m):
    sys.stderr.write(m + "\n"); sys.exit(1)

def need():
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        die("ffmpeg not found. Install it: apt install -y ffmpeg (Pi) or brew install ffmpeg (Mac)")

def probe(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,avg_frame_rate,nb_frames:format=duration",
        "-of", "json", path], capture_output=True, text=True)
    if r.returncode != 0: die("ffprobe could not read " + path)
    d = json.loads(r.stdout)
    s = d["streams"][0]
    n, den = (s.get("avg_frame_rate") or "0/1").split("/")
    fps = float(n) / float(den) if float(den) else 0.0
    dur = float(d.get("format", {}).get("duration") or 0)
    return int(s["width"]), int(s["height"]), fps, dur

def c256(r, g, b):
    # 6x6x6 cube, or grey ramp for near-grey colors
    if abs(r - g) < 10 and abs(g - b) < 10:
        v = (r + g + b) // 3
        if v < 4: return 16
        if v > 247: return 231
        return 232 + (v - 4) * 24 // 244
    return 16 + 36 * (r * 6 // 256) + 6 * (g * 6 // 256) + (b * 6 // 256)

def render(buf, w, h, tc):
    # h is even. Each text row = 2 pixel rows, top pixel = foreground of upper half block, bottom = background.
    out = []
    for y in range(0, h, 2):
        line = []
        last = None
        for x in range(w):
            i = (y * w + x) * 3
            j = ((y + 1) * w + x) * 3
            t = (buf[i], buf[i + 1], buf[i + 2])
            b = (buf[j], buf[j + 1], buf[j + 2])
            if tc:
                key = (t, b)
                if key != last:
                    line.append("\x1b[38;2;%d;%d;%d;48;2;%d;%d;%dm" % (t + b))
                    last = key
            else:
                key = (c256(*t), c256(*b))
                if key != last:
                    line.append("\x1b[38;5;%d;48;5;%dm" % key)
                    last = key
            line.append("\u2580")
        line.append("\x1b[0m")
        out.append("".join(line))
    return "\n".join(out)

def dims(path, cols):
    w0, h0, fps, dur = probe(path)
    w = cols
    h = int(round(h0 * w / w0))
    h -= h % 2
    if h < 2: h = 2
    return w, h, fps, dur

def frames(path, w, h, fps):
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-vf", (("fps=%s," % fps) if fps else "") + "scale=%d:%d:flags=area" % (w, h),
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    size = w * h * 3
    while True:
        b = p.stdout.read(size)
        while b and len(b) < size:
            more = p.stdout.read(size - len(b))
            if not more: break
            b += more
        if len(b) < size: break
        yield b
    p.stdout.close(); p.wait()

def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__); return
    need()
    tc = os.environ.get("COLORTERM", "") in ("truecolor", "24bit")
    fps_opt = None; cols = None; path = None
    i = 0
    while i < len(a):
        if a[i] == "-256": tc = False
        elif a[i] == "-tc": tc = True
        elif a[i] == "-fps": i += 1; fps_opt = float(a[i])
        elif a[i].isdigit(): cols = int(a[i])
        else: path = a[i]
        i += 1
    if not path or not os.path.exists(path): die("file not found: %s" % path)
    tsz = shutil.get_terminal_size((80, 24))
    if cols is None:
        cols = tsz.columns
        # also fit the height
        w0, h0, _, _ = probe(path)
        maxrows = max(tsz.lines - 1, 4)
        cols = max(4, min(cols, int(maxrows * 2 * w0 / h0)))
    ext = os.path.splitext(path)[1].lower()
    is_video = ext in (".mp4", ".mov", ".mkv", ".webm", ".avi", ".gif", ".m4v")
    w, h, fps, dur = dims(path, cols)
    if not is_video:
        for b in frames(path, w, h, None):
            print(render(b, w, h, tc)); break
        else:
            die("could not decode image")
        return
    fps = min(fps_opt or fps or 15, fps_opt or 15)
    cache = "%s.%d.%s.%g.ubv" % (path, w, "tc" if tc else "256", fps)
    if not os.path.exists(cache) or os.path.getmtime(cache) < os.path.getmtime(path):
        sys.stderr.write("Converting %s (one time, saved to %s)...\n" % (path, cache))
        tmp = cache + ".part"
        n = 0
        with open(tmp, "wb") as f:
            f.write(b"UBV1" + struct.pack("<dI", fps, 0))
            for b in frames(path, w, h, fps):
                z = zlib.compress(render(b, w, h, tc).encode("utf-8"), 1)
                f.write(struct.pack("<I", len(z))); f.write(z)
                n += 1
                if n % 30 == 0: sys.stderr.write("\r%d frames" % n); sys.stderr.flush()
            f.seek(12); f.write(struct.pack("<I", n))
        os.replace(tmp, cache)
        sys.stderr.write("\rdone, %d frames\n" % n)
    play(cache)

def play(cache):
    f = open(cache, "rb")
    if f.read(4) != b"UBV1": die("bad cache file")
    fps, n = struct.unpack("<dI", f.read(12))
    data = []
    for _ in range(n):
        ln = struct.unpack("<I", f.read(4))[0]
        data.append(zlib.decompress(f.read(ln)).decode("utf-8"))
    out = sys.stdout
    out.write("\x1b[?25l\x1b[2J"); out.flush()
    try:
        t0 = time.monotonic()
        k = 0
        while k < n:
            idx = int((time.monotonic() - t0) * fps)
            if idx >= n: break
            if idx >= k:
                out.write("\x1b[H" + data[idx]); out.flush()
                k = idx + 1
            nxt = t0 + k / fps - time.monotonic()
            if nxt > 0: time.sleep(nxt)
    except KeyboardInterrupt:
        pass
    finally:
        out.write("\x1b[0m\x1b[?25h\n"); out.flush()

main()
