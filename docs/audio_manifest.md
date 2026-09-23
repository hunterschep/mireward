# Original sound assets

`tools/generate_audio.py` synthesizes all audio locally using Python's standard library. The committed source assets are 28 mono, 16-bit, 22,050 Hz PCM WAVs under `assets/audio/`, totaling 5,039,656 bytes. No recordings, sample packs, external services or existing melodies are used. The project contributors dedicate these assets to CC0-1.0 in `assets/audio/LICENSE.txt`.

`assets/audio/manifest.json` records each exact path, intended bus, loop flag, duration, peak/RMS amplitude and SHA-256. It contains 21 gameplay/UI cues, six twelve-second zone beds and one original twenty-four-second drone/instrument phrase. Bell cue IDs match the existing crypt calls. The six zones are village, forest, monastery, inn, crypt and undercroft.

Reproduce with `python3 tools/generate_audio.py`; verify identical committed bytes without writing with `python3 tools/generate_audio.py --check`. Normal Godot import creates the runtime streams. Mixing and loop ownership belong to AudioService; source files do not autoplay.

Root verification: deterministic regeneration/check passed, all WAV headers/durations match the manifest, every file has nonzero samples and peak amplitude at most0.55, and the pinned Godot editor imported all28 without errors. These checks establish source integrity and headroom. Listening, runtime cue coverage and the final game mix remain T24 acceptance work.
