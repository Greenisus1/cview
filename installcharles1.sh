#!/bin/sh
# Pocket TTS Charles installer. Root on 64-bit DietPi, no cloud speech.
# Code: Pocket TTS by Kyutai (MIT); model and Charles/VCTK voice: CC BY 4.0.
# https://huggingface.co/kyutai/pocket-tts-without-voice-cloning
# https://huggingface.co/kyutai/tts-voices
set -eu
[ "$(id -u)" = 0 ] || { echo "Run in the Pi root@DietPi window, not the Mac."; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "Needs 64-bit ARM64 DietPi (aarch64)."; exit 1; }
command -v systemctl >/dev/null || { echo "Needs systemd."; exit 1; }
if [ -e /opt/charles-tts/.installed-v1 ]; then
    echo "Already installed. Run runvoice2"; exit 0
fi
AVAILABLE=$(df -Pk /opt | awk 'NR==2 {print $4}')
[ "$AVAILABLE" -ge 3000000 ] || { echo "Free at least 3 GB on the system drive first."; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends python3-venv ffmpeg ca-certificates
umask 077
mkdir -p /opt/charles-tts/cache /root/tts-audio
python3 -m venv /opt/charles-tts/venv
/opt/charles-tts/venv/bin/pip install --upgrade pip
# Use official CPU-only wheels; default Linux torch may pull CUDA dependencies.
/opt/charles-tts/venv/bin/pip install --no-cache-dir --only-binary=:all: torch==2.11.0 --index-url https://download.pytorch.org/whl/cpu
/opt/charles-tts/venv/bin/pip install --no-cache-dir pocket-tts==3.3.0 soundfile==0.14.0 --extra-index-url https://download.pytorch.org/whl/cpu
export HF_HOME=/opt/charles-tts/cache
# Download built-in Charles/model into the private cache, not all languages.
/opt/charles-tts/venv/bin/python - <<'PYDOWNLOAD'
import torch
from pocket_tts import TTSModel
torch.set_num_threads(2)
model = TTSModel.load_model(language="english")
model.get_state_for_audio_prompt("charles")
print("Charles downloaded. No voice cloning or API key needed.")
PYDOWNLOAD
cat > /opt/charles-tts/charles.py <<'PYCODE'
#!/usr/bin/env python3
"""Local-only Pocket TTS Charles with a warm voice and MP3 output."""
import argparse, json, os, re, socket, struct, sys, tempfile, time, wave
from pathlib import Path
import subprocess
BASE = Path(os.environ.get('TTS_BASE', '/opt/charles-tts'))
SOCK = os.environ.get('TTS_SOCKET', '/run/charles-tts/tts.sock')
OUT = Path(os.environ.get('TTS_OUTPUT', '/root/tts-audio'))
MAX = 10_000

def spoken_text(text):
    """Remove explicit LLM reasoning blocks. Untagged prose cannot be classified."""
    # An unclosed reasoning block is discarded through the end of the input.
    text = re.sub(r"<(think|thinking|analysis|reasoning)\b[^>]*>.*?(?:</\1\s*>|\Z)",
                  "", text, flags=re.IGNORECASE | re.DOTALL)
    text = re.sub(r"</(?:think|thinking|analysis|reasoning)\s*>", "", text, flags=re.IGNORECASE)
    return text.strip()

def prepare_text(text):
    text = spoken_text(text)
    text = re.sub(r"\[([^\]]+)\]\(https?://[^)]+\)", r"\1", text)
    text = text.replace("**", "").replace("__", "").replace("`", "")
    lines = []
    for line in text.splitlines():
        line = re.sub(r"^\s*(?:#{1,6}\s+|[-*+]\s+|\d+[.)]\s+)", "", line).strip()
        if not line:
            continue
        if line[-1] not in ".!?;:":
            line += "."
        lines.append(line)
    return " ".join(lines)

def sentence_chunks(text, limit=350):
    # Keep long unpunctuated lists from becoming a single unstable utterance.
    for sentence in re.split(r"(?<=[.!?;])\s+", text):
        words = sentence.split()
        chunk = []
        size = 0
        for word in words:
            if chunk and size + len(word) + 1 > limit:
                yield " ".join(chunk)
                chunk = []
                size = 0
            chunk.append(word)
            size += len(word) + 1
        if chunk:
            yield " ".join(chunk)

def recv_exact(conn, n):
    result = bytearray()
    while len(result) < n:
        chunk = conn.recv(n - len(result))
        if not chunk:
            raise ConnectionError('Connection closed')
        result.extend(chunk)
    return bytes(result)

def receive(conn):
    n = struct.unpack('!I', recv_exact(conn, 4))[0]
    if n > 1_000_000:
        raise ValueError('Request too large')
    return json.loads(recv_exact(conn, n))

def send(conn, data):
    blob = json.dumps(data).encode()
    conn.sendall(struct.pack('!I', len(blob)) + blob)

def serve():
    import torch
    import soundfile as sf
    from pocket_tts import TTSModel
    torch.set_num_threads(2)
    torch.set_num_interop_threads(1)
    start = time.monotonic()
    model = TTSModel.load_model(language="english")
    voice = model.get_state_for_audio_prompt("charles")
    OUT.mkdir(parents=True, exist_ok=True, mode=0o700)
    Path(SOCK).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if Path(SOCK).exists():
        Path(SOCK).unlink()
    with socket.socket(socket.AF_UNIX) as listener:
        listener.bind(SOCK)
        os.chmod(SOCK, 0o600)
        listener.listen(8)
        print(f'Voice ready in {time.monotonic()-start:.2f}s; two CPU threads; no network listener.', flush=True)
        while True:
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(1800)
                try:
                    request = receive(conn)
                    text = request.get('text', '')
                    if not isinstance(text, str) or not text.strip():
                        raise ValueError('Enter some text first')
                    text = prepare_text(text)
                    if not text:
                        raise ValueError('No final answer to speak after removing thinking')
                    if len(text) > MAX:
                        raise ValueError(f'Text is limited to {MAX} characters per request')
                    name = request.get('output') or f'speech-{time.strftime("%Y%m%d-%H%M%S")}-{time.time_ns()%1000000:06d}.mp3'
                    if not isinstance(name, str) or Path(name).name != name or not name.endswith('.mp3'):
                        raise ValueError('Output must be a plain .mp3 filename, without a folder')
                    destination = OUT / name
                    if destination.exists():
                        raise ValueError('Output already exists. Choose a new filename.')
                    started = time.monotonic()
                    with tempfile.TemporaryDirectory(prefix='.tts-', dir=OUT) as tmp:
                        wav = Path(tmp) / 'speech.wav'
                        mp3 = Path(tmp) / 'speech.mp3'
                        # Stream completed chunks to disk; no artificial breath samples.
                        with sf.SoundFile(str(wav), "w", samplerate=model.sample_rate,
                                          channels=1, subtype="PCM_16") as wav_file:
                            for chunk in sentence_chunks(text, limit=300):
                                audio = model.generate_audio(voice, chunk)
                                wav_file.write(audio.detach().cpu().numpy())
                        subprocess.run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error',
                                        '-threads', '1', '-i', str(wav), '-codec:a', 'libmp3lame',
                                        '-b:a', '96k', str(mp3)], check=True)
                        # Atomic, refuses to overwrite existing files.
                        os.link(mp3, destination)
                    send(conn, {'ok': True, 'file': str(destination), 'seconds': round(time.monotonic()-started, 2)})
                except Exception as exc:
                    try:
                        send(conn, {'ok': False, 'error': str(exc)})
                    except (OSError, ConnectionError):
                        pass

def main():
    parser = argparse.ArgumentParser(description='Generate an offline MP3. No text argument prompts you interactively.')
    parser.add_argument('--serve', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--file', type=Path, help='Read UTF-8 text from a file')
    parser.add_argument('--output', help='New .mp3 filename inside the audio folder')
    parser.add_argument('text', nargs='*')
    args = parser.parse_args()
    if args.serve:
        serve()
        return
    if args.file:
        text = args.file.read_text(encoding='utf-8')
    elif args.text:
        text = ' '.join(args.text)
    elif sys.stdin.isatty():
        text = input('Text to speak: ')
    else:
        text = sys.stdin.read()
    try:
        with socket.socket(socket.AF_UNIX) as conn:
            conn.settimeout(1800)
            conn.connect(SOCK)
            send(conn, {'text': text, 'output': args.output})
            result = receive(conn)
    except (OSError, ConnectionError) as exc:
        print(f'TTS is not ready: {exc}. Check systemctl status charles-tts', file=sys.stderr)
        sys.exit(1)
    if not result.get('ok'):
        print(result.get('error', 'TTS failed'), file=sys.stderr)
        sys.exit(1)
    print(result['file'])

if __name__ == '__main__':
    main()
PYCODE
cat > /usr/local/bin/saycharles.sh <<'WRAPPER'
#!/bin/sh
exec /opt/charles-tts/venv/bin/python /opt/charles-tts/charles.py "$@"
WRAPPER
chmod 755 /usr/local/bin/saycharles.sh
if [ -e /usr/local/bin/runvoice2 ]; then
    cp -p /usr/local/bin/runvoice2 /opt/charles-tts/runvoice2.previous
fi
cp /usr/local/bin/saycharles.sh /usr/local/bin/runvoice2
chmod 755 /usr/local/bin/runvoice2
cat > /etc/systemd/system/charles-tts.service <<'SERVICE'
[Unit]
Description=Offline Pocket TTS Charles MP3 voice
After=local-fs.target
[Service]
Type=simple
Environment=HF_HOME=/opt/charles-tts/cache
Environment=HF_HUB_OFFLINE=1
Environment=TOKENIZERS_PARALLELISM=false
ExecStart=/opt/charles-tts/venv/bin/python /opt/charles-tts/charles.py --serve
RuntimeDirectory=charles-tts
RuntimeDirectoryMode=0700
UMask=0077
Nice=10
CPUQuota=150%
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/root/tts-audio /opt/charles-tts/cache
RestrictAddressFamilies=AF_UNIX
[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable charles-tts
systemctl restart charles-tts
n=0
until [ -S /run/charles-tts/tts.sock ]; do
    n=$((n+1))
    if [ "$n" -ge 90 ]; then
        echo "Voice did not start. Run: journalctl -u charles-tts -n 30"; exit 1
    fi
    sleep 1
done
saycharles.sh Good morning. Good night, Bella.
touch /opt/charles-tts/.installed-v1
echo "Installed. Run runvoice2 and type text. MP3s go in /root/tts-audio."
