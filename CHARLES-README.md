# Charles offline voice for 64-bit DietPi

Pocket TTS Charles, the male voice used in the sample. No artificial breath effects, cloud speech, API key, subscription or voice cloning. Download once, then generate MP3s locally.

## Install on the Pi

Run in the Pi's root@DietPi terminal, not the Mac. Requires 64-bit ARM64 DietPi, Python 3.10-3.14, systemd, internet for installation, and at least 3 GB free system-disk space.

Download `installcharles1.sh` from this repository, then:

```sh
sh installcharles1.sh
runvoice2
```

Type text at the prompt. It prints a new MP3 path in `/root/tts-audio`.

```sh
runvoice2 Hello from the Pi
runvoice2 --file story.txt
runvoice2 --file story.txt --output story.mp3
```

Use the prompt or a text file for shell special characters. Existing MP3s are never overwritten. `saycharles.sh` is an alias. The previous `say.sh` installation remains intact. If `runvoice2` already exists in `/usr/local/bin`, the installer backs it up to `/opt/charles-tts/runvoice2.previous` before replacing it.

## Runtime

A warm local service holds the voice in memory. Two CPU threads, low priority and a 1.5-core CPU cap reduce interference with other Pi apps. A private Unix socket is used, not a web server. The service runs in offline mode and does not send text anywhere. Marked thinking blocks and Markdown decorations are removed before speech. There are no fake breath clips. Output is limited to 10,000 text characters per request.

The model/Charles embedding/tokenizer are about 226 MB, below 5 GB. Python, CPU-only PyTorch and other install dependencies are additional. Full ARM64 Python 3.13 binary dependency resolution was checked. The script uses the official CPU-only PyTorch index to avoid CUDA packages.

Local CPU testing generated 8.48 seconds of audio in 3.88 seconds with two threads, about 982 MB peak process RAM. These are not Raspberry Pi benchmark numbers. Actual Pi installation is not yet verified. Running beside a large Ollama model can be slower or use too much memory. Stop unused voices if needed:

```sh
systemctl stop offline-tts
```

Optional previous male/breath services can also be stopped if installed. Do not stop other apps or Ollama without deciding you want them stopped.

```sh
systemctl status charles-tts
journalctl -u charles-tts -n 30
systemctl restart charles-tts
systemctl disable --now charles-tts
```

## Attribution and licence

- Pocket TTS implementation by Kyutai and contributors, MIT: https://github.com/kyutai-labs/pocket-tts
- Pocket TTS without-voice-cloning weights by Kyutai, CC BY 4.0: https://huggingface.co/kyutai/pocket-tts-without-voice-cloning
- Charles voice is the VCTK p254_023_enhanced voice supplied by Kyutai, CC BY 4.0: https://huggingface.co/kyutai/tts-voices/blob/main/vctk/p254_023_enhanced.wav
- Voice dataset/licence notes: https://huggingface.co/kyutai/tts-voices
- CC BY 4.0: https://creativecommons.org/licenses/by/4.0/

The installer downloads upstream model/voice files into a private cache. It does not claim they were trained by this project's author. Retain these credits when sharing this setup; provide attribution appropriate to your use of the model/voice. Generated speech must not be presented deceptively as a real person's recording.
