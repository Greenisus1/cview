# Offline MP3 voice for 64-bit DietPi

Piper neural speech with the US English female LJSpeech-medium voice. Generates MP3s locally after an initial internet-connected install. No API key, cloud speech, email, or automatic file transfer.

## Install

Run in the Pi's root@DietPi terminal, not the Mac terminal. Needs at least 800 MB free disk space and 64-bit ARM64 Linux. The installer uses an isolated Python environment, not the system Python packages.

Download `installtts.sh` from this repository, then run:

```sh
sh installtts.sh
```

## Speak

```sh
say.sh
```

Type your text at the prompt. Or use:

```sh
say.sh Hello from the Pi
say.sh --file story.txt
say.sh --file story.txt --output story.mp3
```

The command prints the MP3's path. Files are in `/root/tts-audio`. Existing recordings are never overwritten. For punctuation and shell special characters, use the interactive prompt or a text file, rather than an unquoted shell command.

## Speed and resources

The systemd service keeps the voice loaded between requests for quick starts. It uses two synthesis threads, low CPU priority, a 1.5-core service CPU cap, and a private Unix socket, not a web port. Requests run one at a time. No background generative model or GPU is needed.

Local x86-64 testing used about 215 MB RAM, with 0.76 seconds for warm-up and 0.23 seconds to make a 3.4-second sample. These are not Raspberry Pi benchmark numbers. ARM64 Python 3.13 binary dependency availability was checked, but actual DietPi installation still needs to be verified on the device.

Disable background loading:

```sh
systemctl disable --now offline-tts
```

Restart or inspect:

```sh
systemctl restart offline-tts
systemctl status offline-tts
journalctl -u offline-tts -n 30
```

## Software and voice

- Piper 1.4.1: https://github.com/OHF-Voice/piper1-gpl (GPL-3.0)
- Voice model card: https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/ljspeech/medium/MODEL_CARD (dataset: public domain)
- FFmpeg performs local MP3 encoding.

This repository contains only the installer, not redistributed voice weights or Piper binaries. The install downloads those from their upstream distributions. Audio stays on this machine unless you transfer it separately.

Explicit `<think>`, `<thinking>`, `<analysis>`, and `<reasoning>` blocks are removed before speech. Unmarked reasoning cannot be detected; feed only final-answer text when connecting an LLM. Successful output is only the MP3 path.
