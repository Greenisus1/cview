# Offline male voice with soft breaths

A custom speech preset built on Piper's HFC male medium model, not a newly trained voice. Makes MP3s on 64-bit DietPi with sentence spacing and quiet, locally generated air-noise breaths between utterances. No downloaded breathing recordings. No cloud speech, email, or automatic file transfer.

## Install

Requires the original `installtts.sh` environment to be installed first. Run in the Pi root terminal, not on the Mac. Needs about 150 MB free space for the add-on; the initial voice download needs internet. Speech works offline afterward.

Download `installttsbreath2.sh` from this repository, then:

```sh
sh installttsbreath2.sh
saybreath.sh
```

Type the text at the prompt. It prints the new MP3 path in `/root/tts-audio`.

```sh
saybreath.sh Hello from the Pi
saybreath.sh --file story.txt
saybreath.sh --file story.txt --output story-with-breaths.mp3
```

Use the prompt or a text file for punctuation and shell special characters. Existing MP3s are not overwritten.

## Behavior

- Removes marked thinking blocks before speaking.
- Cleans Markdown list markers, emphasis, and link destinations.
- Adds missing punctuation to nonempty lines.
- Splits long input into bounded chunks to reduce long-utterance problems.
- Adds about 0.30-0.32 seconds of quiet spacing and soft synthetic breathing between chunks, not before the first or after the last.
- Keeps the voice warm, with two synthesis threads and a 1.5-core service CPU cap.

Local x86 test produced a 13-second sample correctly including “Bella.” The service used about 223 MB RAM. These are not Pi benchmarks. Names and unusual words can still need pronunciation adjustments; this is not a claim that all voice glitches are fixed.

The new service is separate and leaves the old voice intact. To avoid holding multiple voices in memory, stop unused services:

```sh
systemctl stop offline-tts
systemctl stop offline-tts-male
```

The second command applies only if that optional male add-on was installed. To stop the new preset:

```sh
systemctl disable --now offline-tts-breath
```

To inspect it:

```sh
systemctl status offline-tts-breath
journalctl -u offline-tts-breath -n 30
```

## Personal-use voice licence

Use this voice for personal, noncommercial speech experiments. Do not sell it or put it into a commercial speech service without clearing the voice rights.

HFC male's model card cites CC BY-NC-SA 4.0 training data and fine-tuning from the Lessac voice. A repository-level MIT label is not proof of unrestricted voice rights. The installer downloads weights from upstream and does not redistribute them in this repository.

- HFC model card: https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/hfc_male/medium/MODEL_CARD
- Dataset licence: https://creativecommons.org/licenses/by-nc-sa/4.0/deed.en
- Piper engine (GPL-3.0): https://github.com/OHF-Voice/piper1-gpl

Synthetic breaths are made from locally generated noise and use no third-party sound clips. The existing voice-model licence caveat still applies.
