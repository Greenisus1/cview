#!/bin/sh
# Male voice with synthetic breaths add-on for the previously installed offline TTS. No file transfers.
# HFC male medium: personal/noncommercial use. CC BY-NC-SA 4.0 training data.
# Model card: https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/hfc_male/medium/MODEL_CARD
# This voice was fine-tuned from Lessac; do not claim commercial rights.
set -eu
if [ "$(id -u)" != 0 ]; then
    echo "Run this in the Pi root@DietPi window, not on the Mac."; exit 1
fi
case "$(uname -m)" in aarch64|x86_64) ;; *) echo "Needs 64-bit ARM64 DietPi (aarch64)."; exit 1 ;; esac
command -v systemctl >/dev/null || { echo "This installer needs systemd."; exit 1; }
if [ -e /opt/offline-tts-breath/.installed ]; then
    echo "Already installed. Run saybreath.sh or systemctl restart offline-tts-breath."; exit 0
fi
AVAILABLE=$(df -Pk /opt | awk 'NR==2 {print $4}')
if [ "$AVAILABLE" -lt 150000 ]; then
    echo "Please free at least 150 MB on the system drive first. Nothing installed."; exit 1
fi
if [ ! -x /opt/offline-tts/venv/bin/python ]; then
    echo "Install the original offline TTS first. This is a male-voice add-on."; exit 1
fi
umask 077
mkdir -p /opt/offline-tts-breath/voices /root/tts-audio
/opt/offline-tts/venv/bin/python -m piper.download_voices en_US-hfc_male-medium --download-dir /opt/offline-tts-breath/voices
cat > /opt/offline-tts-breath/tts.py <<'PYCODE'
#!/usr/bin/env python3
"""Local-only Piper TTS with a warm voice and MP3 output."""
import argparse, json, os, re, socket, struct, sys, tempfile, time, wave
from pathlib import Path
import subprocess
BASE = Path(os.environ.get('TTS_BASE', '/opt/offline-tts-breath'))
SOCK = os.environ.get('TTS_SOCKET', '/run/offline-tts-breath/tts.sock')
OUT = Path(os.environ.get('TTS_OUTPUT', '/root/tts-audio'))
MAX = 200_000

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

def breath_gap(sample_rate, index):
    """Low-volume synthetic air noise; no recorded breathing or online audio."""
    import numpy as np
    duration = 0.22 + (index % 3) * 0.02
    count = int(sample_rate * duration)
    rng = np.random.default_rng(731 + index)
    noise = rng.standard_normal(count)
    # Colored noise: remove rumble and soften harsh high frequencies.
    smooth = np.convolve(noise, np.ones(5) / 5, mode="same")
    low = np.convolve(smooth, np.ones(65) / 65, mode="same")
    air = smooth - low
    envelope = np.sin(np.linspace(0, np.pi, count)) ** 1.8
    rms = max(float(np.sqrt(np.mean(air * air))), 0.000001)
    air = air / rms * 0.006 * envelope
    pcm = np.clip(air * 32767, -32767, 32767).astype("<i2").tobytes()
    before = b"\x00\x00" * int(sample_rate * 0.12)
    after = b"\x00\x00" * int(sample_rate * 0.22)
    return before + pcm + after

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
    from piper.config import PiperConfig, SynthesisConfig
    model = BASE / 'voices/en_US-hfc_male-medium.onnx'
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
                        with wave.open(str(wav), 'wb') as wav_file:
                            wav_file.setnchannels(1)
                            wav_file.setsampwidth(2)
                            wav_file.setframerate(voice.config.sample_rate)
                            chunks = list(sentence_chunks(text))
                            for index, chunk in enumerate(chunks):
                                voice.synthesize_wav(chunk, wav_file, set_wav_format=False,
                                    syn_config=SynthesisConfig(length_scale=1.0, noise_scale=0.333, noise_w_scale=0.8))
                                # No breath before the first sentence or after the last.
                                if index < len(chunks) - 1:
                                    wav_file.writeframes(breath_gap(voice.config.sample_rate, index))
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
        print(f'TTS is not ready: {exc}. Check systemctl status offline-tts-breath', file=sys.stderr)
        sys.exit(1)
    if not result.get('ok'):
        print(result.get('error', 'TTS failed'), file=sys.stderr)
        sys.exit(1)
    print(result['file'])

if __name__ == '__main__':
    main()
PYCODE
cat > /usr/local/bin/saybreath.sh <<'SHCODE'
#!/bin/sh
exec /opt/offline-tts/venv/bin/python /opt/offline-tts-breath/tts.py "$@"
SHCODE
chmod 755 /usr/local/bin/saybreath.sh
cat > /etc/systemd/system/offline-tts-breath.service <<'SERVICE'
[Unit]
Description=Offline Piper MP3 voice (local-only)
After=local-fs.target
[Service]
Type=simple
ExecStart=/opt/offline-tts/venv/bin/python /opt/offline-tts-breath/tts.py --serve
Restart=on-failure
RestartSec=3
RuntimeDirectory=offline-tts-breath
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
systemctl enable --now offline-tts-breath
n=0
until [ -S /run/offline-tts-breath/tts.sock ]; do
    n=$((n+1))
    if [ "$n" -ge 60 ]; then
        echo "Voice did not start. Run: journalctl -u offline-tts-breath -n 30"; exit 1
    fi
    sleep 1
done
saybreath.sh Offline voice ready. This MP3 was generated on this computer.
touch /opt/offline-tts-breath/.installed
echo "Installed. Run saybreath.sh and type your text. MP3s go in /root/tts-audio."
