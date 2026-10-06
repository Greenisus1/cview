# cview: terminal media and Raspberry Pi tools

View images and videos as colored text blocks in a terminal, play Road Dodge, or browse the separate Pi setup and speech tools in this repository.

Start with the viewer or game. The service installers and site patches are separate, system-changing tools, not required for either quickstart.

## Terminal image and video viewer

`cview.py` renders images with Unicode half-blocks and ANSI color. Videos are converted to a compressed terminal-frame cache before playback. Requires Python 3, `ffmpeg`, `ffprobe`, and a terminal with color and Unicode support.

On a Debian-based Pi, install the media dependency if needed:

```sh
sudo apt install ffmpeg
```

Download and show an image:

```sh
wget -O cview.py https://raw.githubusercontent.com/Greenisus1/cview/main/cview.py
python3 cview.py photo.png
```

Video and display options:

```sh
python3 cview.py clip.mp4
python3 cview.py photo.png 80 -256
python3 cview.py clip.mp4 80 -fps 10 -tc
```

- The optional number is the output width in columns. Without it, the viewer tries to fit the terminal.
- `-256` uses 256-color output; `-tc` forces true color.
- `-fps N` sets the video frame rate. Default playback is capped at 15 fps.
- Converted videos create a `.ubv` cache next to the source. That folder must be writable, and caches use extra disk space. Delete the cache to reclaim space; it will be rebuilt on the next run.
- Press Ctrl+C to stop video playback.
- Known issue: `--help` currently prints `None`. Use the examples above. This README update does not change the viewer's code.

## Road Dodge

A small Bash terminal driving game. Dodge `#` obstacles, keep your three lives, and build a score. Requires Bash, `awk`, `tput`, `stty`, and an interactive terminal. No Python or media packages required.

Run on the Pi:

```sh
wget -O roaddodge2.sh https://raw.githubusercontent.com/Greenisus1/cview/main/roaddodge2.sh
bash roaddodge2.sh
```

| Key | Action |
| --- | --- |
| A / left arrow | Steer left |
| D / right arrow | Steer right |
| W / up arrow | Temporary speed boost |
| Q | Quit |

Do not run with `sh`: the game uses Bash arrays. If the terminal is left in a strange state after an interruption, run `stty sane` and `reset`.

## Project index

| Files | Purpose and requirements |
| --- | --- |
| `cview.py` | Terminal media viewer; Python 3 and ffmpeg/ffprobe |
| `roaddodge2.sh` | Bash driving game; interactive terminal |
| `monitor.sh` | Linux live system/service monitor; `/proc`, optional `vcgencmd`; Ctrl+C stops it |
| `keys.py`, `keys2.py` | Local encrypted vault tools; Python 3 and `cryptography`; review their usage before saving secrets |
| `installtts.sh` | Piper speech installer; root, systemd, 64-bit Linux; see [TTS guide](TTS-README.md) |
| `installttsbreath1.sh`, `installttsbreath2.sh` | Speech add-ons; see [breath preset guide](TTS-BREATH-README.md) for the documented version |
| `installcharles1.sh` | Charles speech installer; root, systemd, ARM64 DietPi; see [Charles guide](CHARLES-README.md) |
| `install-all.sh`, `install-all2.sh`, `RUNAPPS.sh`, `RUNAPPS2.sh`, `autostart.sh` | Crunchbyte/Ollama/tunnel setup and service scripts; system-specific, not general viewer dependencies |
| `cbpatch7.py` through `cbpatch13.py` | Versioned site patches that depend on an existing Crunchbyte installation |

## Safety and test status

- Review downloaded code before running it. Setup scripts install packages, write systemd units, or change running services. Read the matching guide and script checks first.
- Keep passwords, API keys, and tunnel tokens out of GitHub, screenshots, and issue logs. A local encrypted vault is not permission to publish its contents.
- Individual tools have different test coverage. Road Dodge and the viewer still need verification on real Pi hardware; do not treat a syntax check or local render as a hardware benchmark.
- The speech guides distinguish local tests from unverified Pi installation. Their disk and architecture requirements differ.
- Older numbered installers and patches are retained. A higher filename number alone does not prove compatibility with your installation.

When reporting a bug, include the filename, command, OS/architecture, and error text. Remove private information from logs. No guarantee of compatibility with every Pi image or terminal.
