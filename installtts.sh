#!/bin/sh
# Installs offline Piper TTS on 64-bit DietPi. No email or file transfers.
set -eu
if [ "$(id -u)" != 0 ]; then
    echo "Run this in the Pi root@DietPi window, not on the Mac."; exit 1
fi
case "$(uname -m)" in aarch64|x86_64) ;; *) echo "Needs 64-bit ARM64 DietPi (aarch64)."; exit 1 ;; esac
command -v systemctl >/dev/null || { echo "This installer needs systemd."; exit 1; }
if [ -e /opt/offline-tts/.installed ]; then
    echo "Already installed. Run say.sh or systemctl restart offline-tts."; exit 0
fi
AVAILABLE=$(df -Pk /opt | awk 'NR==2 {print $4}')
if [ "$AVAILABLE" -lt 800000 ]; then
    echo "Please free at least 800 MB on the system drive first. Nothing installed."; exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends python3-venv ffmpeg ca-certificates
umask 077
mkdir -p /opt/offline-tts/voices /root/tts-audio
python3 -m venv /opt/offline-tts/venv
/opt/offline-tts/venv/bin/pip install --no-cache-dir --only-binary=:all: piper-tts==1.4.1 onnxruntime==1.23.2
/opt/offline-tts/venv/bin/python -m piper.download_voices en_US-ljspeech-medium --download-dir /opt/offline-tts/voices
cat > /opt/offline-tts/tts.py <<'PYCODE'
#!/usr/bin/env python3
"""Local-only Piper TTS with a warm voice and MP3 output."""
import argparse, json, os, re, socket, struct, sys, tempfile, time, wave
from pathlib import Path
import subprocess
BASE = Path(os.environ.get('TTS_BASE', '/opt/offline-tts'))
SOCK = os.environ.get('TTS_SOCKET', '/run/offline-tts/tts.sock')
OUT = Path(os.environ.get('TTS_OUTPUT', '/root/tts-audio'))
MAX = 200_000

def spoken_text(text):
    """Remove explicit LLM reasoning blocks. Untagged prose cannot be classified."""
    # An unclosed reasoning block is discarded through the end of the input.
    text = re.sub(r"<(think|thinking|analysis|reasoning)\b[^>]*>.*?(?:</\1\s*>|\Z)",
                  "", text, flags=re.IGNORECASE | re.DOTALL)
    text = re.sub(r"</(?:think|thinking|analysis|reasoning)\s*>", "", text, flags=re.IGNORECASE)
    return text.strip()

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
    import onnxruntime as ort
    from piper import PiperVoice
    from piper.config import PiperConfig
    model = BASE / 'voices/en_US-ljspeech-medium.onnx'
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 2
    opts.inter_op_num_threads = 1
    opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    start = time.monotonic()
    voice = PiperVoice(session=ort.InferenceSession(str(model), sess_options=opts,
                       providers=['CPUExecutionProvider']),
                       config=PiperConfig.from_dict(json.loads(Path(str(model) + '.json').read_text())))
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
                    text = spoken_text(text)
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
                        with wave.open(str(wav), 'wb') as wav_file:
                            voice.synthesize_wav(text, wav_file)
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
        print(f'TTS is not ready: {exc}. Check systemctl status offline-tts', file=sys.stderr)
        sys.exit(1)
    if not result.get('ok'):
        print(result.get('error', 'TTS failed'), file=sys.stderr)
        sys.exit(1)
    print(result['file'])

if __name__ == '__main__':
    main()
PYCODE
cat > /usr/local/bin/say.sh <<'SHCODE'
#!/bin/sh
exec /opt/offline-tts/venv/bin/python /opt/offline-tts/tts.py "$@"
SHCODE
chmod 755 /usr/local/bin/say.sh
cat > /etc/systemd/system/offline-tts.service <<'SERVICE'
[Unit]
Description=Offline Piper MP3 voice (local-only)
After=local-fs.target
[Service]
Type=simple
ExecStart=/opt/offline-tts/venv/bin/python /opt/offline-tts/tts.py --serve
Restart=on-failure
RestartSec=3
RuntimeDirectory=offline-tts
RuntimeDirectoryMode=0700
UMask=0077
Nice=10
CPUQuota=150%
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/root/tts-audio
ProtectHome=read-only
RestrictAddressFamilies=AF_UNIX
[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable --now offline-tts
n=0
until [ -S /run/offline-tts/tts.sock ]; do
    n=$((n+1))
    if [ "$n" -ge 60 ]; then
        echo "Voice did not start. Run: journalctl -u offline-tts -n 30"; exit 1
    fi
    sleep 1
done
say.sh Offline voice ready. This MP3 was generated on this computer.
touch /opt/offline-tts/.installed
echo "Installed. Run say.sh and type your text. MP3s go in /root/tts-audio."
