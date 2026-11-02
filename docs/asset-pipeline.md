# Asset Pipeline

The tooling that processes raw assets and generates game metadata lives in
`scripts/` and is **run from the repository root**.

## Repository Structure & Asset Separation

Third-party game assets and raw design files are isolated in a private git
submodule at `src/data`:

- **Raw sources** (`src/data/raw/`): Original sound packs, raw audio files, and source art. Contains `.gdignore` to prevent Godot from importing unnecessary raw files.
- **Binary outputs** (`src/data/assets/`): Processed sprite sheets, sound effects (`.wav`), fonts (`.ttf`), and their Godot `.import` files.
- **Public resources** (`src/`): Godot project files, scripts (`.gd`), scenes (`.tscn`), and theme configurations (`.tres`).

## Environment Setup (One Time)

Audio processing requires Python 3.10+ and [ffmpeg](https://ffmpeg.org) on `PATH`.

From the repository root:

```powershell
.\scripts\setup_env.ps1
```

This creates `.venv` at the repository root and installs dependencies from `scripts/requirements.txt`.

## Sound Building

Sound effects are normalized, trimmed, and converted via `scripts/build_sounds.py` using `pydub`.

Manifest configurations are stored in `scripts/config/sounds.json`:

```json
{
  "Click": {
    "file": "src/data/raw/sounds/Click.wav",
    "output": "src/data/assets/sounds/Click.wav"
  }
}
```

Run the sound builder from the root:

```powershell
.\scripts\build_sounds.ps1
```

The script will process each sound and output game-ready audio into `src/data/assets/sounds/`.

## Build Info Generation

Generates git revision, tag/commit, and build timestamp metadata used by the in-game About panel and build overlays:

```powershell
.\scripts\gen_build_info.ps1
```

Outputs metadata to `src/build_info/build_info.json`.

## Godot Verification

To verify that all assets and scenes load cleanly without headless errors:

```powershell
godot.cmd --path src --headless --quit
```
