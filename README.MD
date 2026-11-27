# Escapeteers
[![License: MIT](https://img.shields.io/badge/License-MIT-478CBF.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Conduct](https://img.shields.io/badge/Conduct-Covenant%202.0-478CBF.svg?style=for-the-badge)](https://www.contributor-covenant.org/version/2/0/code_of_conduct/)
[![Made with Godot](https://img.shields.io/badge/GODOT-4.7-478CBF?style=for-the-badge&logo=godot%20engine&logoColor=white)](https://godotengine.org)

<p align="center">
  <a href="https://youtu.be/E95BCyRuTGU">
    <img src="screens/cover.jpg" alt="Escapeteers">
  </a>
</p>

> **Escapeteers** is a top-down squad bullet heaven & horde survival game. Lead a frantic, auto-firing fellowship of survivors through an endless, dynamically generated dungeon.

## Assets

Game assets are not distributed with this source. They are third-party works governed by their own license terms, credited below, and several of them may not be redistributed — so they live in a separate, private repository referenced here as a git submodule at `src/data`.

Each release of the game pins the exact asset revision it was built with, so any tagged version can be rebuilt with the assets it originally shipped.

```bash
git clone --recurse-submodules <this-repo>

# already cloned without submodules
git submodule update --init
```

The submodule is private: without access, the clone succeeds but `src/data` stays empty and the project will not run. The credits below list every asset used and where it came from, so the set can be reassembled from the original sources. Arrange them under `src/data/assets/` and `src/data/raw/`.

## Credits

### Graphics

#### Tiny RPG Character Asset Pack (Heroes)
* **Author:** [Zerie](https://zerie.itch.io/)
* **Source:** [Itch.io](https://zerie.itch.io/tiny-rpg-character-asset-pack)
* **License:** Paid. Used under a purchased license (personal and commercial use allowed; redistribution and resale prohibited).

#### Tiny RPG Character Asset Pack 02 (Enemies)
* **Author:** [Zerie](https://zerie.itch.io/)
* **Source:** [Itch.io](https://zerie.itch.io/tiny-rpg-character-asset-pack-02)
* **License:** Paid. Used under a purchased license (personal and commercial use allowed; redistribution and resale prohibited).

#### Pixel Top Down Dungeon
* **Author:** [MrDakerChan](https://mrdakerchan.itch.io/)
* **Source:** [Itch.io](https://mrdakerchan.itch.io/pixel-top-down-dungeon)
* **License:** Paid. Used under a purchased license (personal and commercial use allowed; redistribution and resale prohibited).

#### 16x16 Dungeon Tileset
* **Author:** [Larchrow](https://larchrow.itch.io/)
* **Source:** [Itch.io](https://larchrow.itch.io/larchrow-16x16-dungeon-tileset)
* **License:** Paid. Royalty-free for commercial and non-commercial use; redistribution and resale prohibited.

#### Pixel UI Theme for Godot
* **Author:** [Pelatho](https://thowsenmedia.itch.io/)
* **Source:** [Itch.io](https://thowsenmedia.itch.io/pixel-ui-theme-for-godot)
* **License:** Paid. Used under a purchased license (personal and commercial use allowed; redistribution and resale prohibited).

#### Godot CRT Shader
* **Author:** [Henrique Alves (perons)](https://perons.itch.io/)
* **Source:** [Itch.io](https://perons.itch.io/godot-crt-shader)
* **License:** Free for personal and commercial use. The shader was purchased to support the author.

#### Kenney Game Assets
* **Author:** [Kenney](https://kenney.nl/)
* **Source:** [Itch.io](https://kenney.itch.io/kenney-game-assets)
* **License:** [Creative Commons Zero (CC0 1.0)](https://creativecommons.org/publicdomain/zero/1.0/) — public domain, free for personal and commercial use.

### Music

#### Three Red Hearts - Prepare to Dev
* **Author:** [Tallbeard Studios (Benjamin Burnes)](https://tallbeard.itch.io/)
* **Source:** [Itch.io](https://tallbeard.itch.io/three-red-hearts-prepare-to-dev)
* **License:** [Creative Commons Zero (CC0 1.0)](https://creativecommons.org/publicdomain/zero/1.0/) — public domain, free for personal and commercial use. The pack was purchased to support the author.

### Sound Effects

#### Pixel Combat
* **Author:** [Helton Yan](https://heltonyan.itch.io/)
* **Source:** [Itch.io](https://heltonyan.itch.io/pixelcombat)
* **License:** Paid. Used under a purchased license (personal and commercial use allowed; purchased to support the author).

#### 200 Free SFX
* **Author:** [Kronbits (Davit Masia)](https://kronbits.itch.io/)
* **Source:** [Itch.io](https://kronbits.itch.io/200-free-sfx)
* **License:** [Creative Commons Zero (CC0 1.0)](https://creativecommons.org/publicdomain/zero/1.0/) — public domain, free for personal and commercial use.

### Fonts

#### m3x6, m5x7, m6x11 & m6x11plus
* **Author:** [Daniel Linssen](https://managore.itch.io/)
* **Source:** [m3x6](https://managore.itch.io/m3x6), [m5x7](https://managore.itch.io/m5x7), [m6x11](https://managore.itch.io/m6x11)
* **License:** Free for personal and commercial use.

---

## Development Tools

All developer tooling lives under `scripts/`. Run commands from the repository root in PowerShell.

| Script | Purpose | Underlying Runner |
| :--- | :--- | :--- |
| `scripts/setup_env.ps1` | Creates `.venv` and installs Python dependencies from `scripts/requirements.txt` (`gdtoolkit`) | `python -m venv` / `pip` |
| `scripts/verify.ps1` | Formats (`gdformat -l 150`), enforces LF endings, lints (`gdlint`), refreshes Godot's class cache (`--import`), and runs strict type checks (`godot --check-only -d`) | `gdtoolkit` + `godot` |
| `scripts/autoplay.ps1` | Runs the zero-overhead `src/autoplay/` suite (CPU/GPU profiler, single-build balance test, parallel multi-build matrix, live replay viewer, and map audit) | `godot` / `scripts/autoplay_parallel.py` |
| `scripts/build_sounds.ps1` | Normalises and bitcrushes sound effects into 16-bit PCM WAVs using `ffmpeg` | `scripts/build_sounds.py` |
| `scripts/gen_build_info.ps1` | Stamps the current commit short SHA and UTC commit timestamp into `src/build_info/build_info.json` | `scripts/gen_build_info.py` |

### Environment & Verification (`setup_env.ps1`, `verify.ps1`)

- `scripts/setup_env.ps1`: Takes no flags. Creates `.venv` if missing and installs `scripts/requirements.txt`.
- `scripts/verify.ps1 <file>...`: Takes one or more `.gd` file paths (positional `-Files` parameter). Runs `gdformat -l 150`, converts CRLF to LF, runs `gdlint`, then runs `godot --import` and `godot --check-only -d` with isolated `.venv/cache/` paths.

```powershell
# Initial Python tooling setup
powershell -ExecutionPolicy Bypass -File .\scripts\setup_env.ps1

# Format, lint, and type-check modified GDScript files
powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1 src\autoplay\autoplay_bot.gd src\autoplay\autoplay_special_rooms.gd
```

### Autoplay, Profiling, Balance & Map Audit (`autoplay.ps1`)

#### Modes

| Mode | Purpose | Defaults |
| :--- | :--- | :--- |
| `perf` | CPU/GPU profiler (subsystem timings, GPU draw calls, VRAM, `PointLight2D` peaks, and top 20 slowest frames) | `3` seeds, immortal squad (`>=65%` HP), gate-rushing, `9000` frames (`150s`) headless (`3600` frames / `60s` with `-Gpu`) |
| `balance` | Single-build mortality, class DPS/HPS, room archetype difficulty, and D01–D12 attrition curve | `20` seeds, real death, `108000` frames (`1800s`) |
| `matrix` | Multi-build sweep across leaders and squad compositions (parallelized headless via `scripts/autoplay_parallel.py`) | `10` seeds per build, `108000` frames (`1800s`), `Min(8, CPU cores)` workers |
| `watch` | Live windowed replay with rendering and audio enabled | `1` seed, `2.0x` speed, unlimited frames (`0`) |
| `audit` | Headless procedural dungeon validator (shortcut overlaps, wall holes/collisions, key/door reachability, full solvability) | `50` seeds, `MaxDepth 12` |

#### Parameters & Flags

| Parameter | Type / Values | Default | Description |
| :--- | :--- | :--- | :--- |
| `-Mode` | `perf \| balance \| matrix \| watch \| audit` | `perf` | Selects which runner mode to execute. |
| `-MatrixSet` | `all \| balanced \| mono \| comps` | `all` | Selects which build set `matrix` runs: `balanced` (`8` leaders), `comps` (`melee_stack`, `ranged_kite`, `random`), `mono` (`8` single-class builds), or `all` (`19` total builds). |
| `-Build` | `balanced \| melee_stack \| ranged_kite \| random \| mono:<hero_id>` | `balanced` | Draft and level-up policy used by the bot (`perf`, `balance`, `watch`). |
| `-Leader` | `archer \| armored_axeman \| knight \| knight_templar \| priest \| soldier \| swordsman \| wizard` | `knight` | Starting hero class (`perf`, `balance`, `watch`). |
| `-Seeds` | `<int>` | Mode default | Number of sequential seeds to run (`3` `perf`, `20` `balance`, `10` `matrix`, `1` `watch`, `50` `audit`; defaults to `1` if `-Seed` is specified without `-Seeds`). |
| `-Seed` | `<int>` | `12345` | Starting dungeon seed (`run_seed = Seed + i`). |
| `-MaxDepth` | `<int>` | `12` | Target dungeon depth used for map generation and win detection. |
| `-MaxFrames` | `<int>` | Mode default | Simulation frame cap at 60Hz (`0` = unlimited). Defaults: `9000` CPU `perf`, `3600` `-Gpu`, `108000` `balance`/`matrix`, `0` `watch`. |
| `-Speed` | `<double>` | `1.0` (`2.0` in `watch`) | `Engine.time_scale` multiplier for faster simulation or replays. |
| `-Immortal` | `"true" \| "false"` | `"true"` in `perf`, `"false"` otherwise | When `"true"`, clamps living squad members' HP at `>=65%` max HP so profiling runs don't end early. |
| `-Jobs` | `<int>` | `Min(8, CPU cores)` for headless `matrix`, `1` otherwise | Parallel Godot worker count for headless `balance` and `matrix` sweeps. |
| `-Out` | `<path.json>` | `""` (none) | Writes full structured JSON telemetry (performance samples/spikes, balance runs/breakdowns, or audit results). |
| `-Gpu` | Switch | Off | Runs windowed with real GPU rendering, disables VSync in `perf` mode, and logs viewport GPU/CPU render times, draw calls, VRAM, and `PointLight2D` counts (forces single-process execution). |
| `-FullCombat` | Switch | Off | Disables gate-rushing in `perf` mode (`rush_deep = false`) so the bot clears rooms and backtracks, profiling patrol repopulation, closing-spike arenas, and potion buffs alongside combat. |

#### Examples

```powershell
# Headless CPU profiling (3 seeds, gate-rush)
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode perf -Seeds 3

# GPU profiling with real rendering, draw calls, lights, and full room combat
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode perf -Gpu -FullCombat -Leader swordsman -Seeds 2 -MaxFrames 24000

# Single-build balance run across 20 seeds
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode balance -Leader knight -Build melee_stack -Seeds 20

# Parallel balanced-only matrix across 10 seeds using 8 workers with JSON export
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode matrix -MatrixSet balanced -Seeds 10 -Seed 12350 -Jobs 8 -Out .venv\cache\balance_matrix.json

# Validate procedural dungeon generation & shortcut tunnels across 100 seeds
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode audit -Seeds 100

# Watch the bot play seed 12345 in a visible window at 2x speed
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode watch -Seed 12345 -Build balanced -Speed 2
```

### Audio Pipeline (`build_sounds.ps1`)

Requires `ffmpeg` on `PATH`. Wraps `scripts/build_sounds.py` and forwards CLI flags:

- `--manifest <path>`: Path to sound manifest JSON (default `scripts/config/sounds.json`).
- `--sample-rate <hz>`: Global sample rate override (e.g., `22050`, `16000`, `11025`).
- `--channels <1|2>`: Global channel count override (`1` mono, `2` stereo).
- `--bits <int>`: Global bit-depth crunch override (e.g., `8` for retro crunch, `16` for clean).

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_sounds.ps1 --manifest scripts\config\sounds.json
```

### Build Metadata (`gen_build_info.ps1`)

Wraps `scripts/gen_build_info.py` to update `src/build_info/build_info.json`:

- No flags: Stamps `"commit"` (short SHA) and `"built_at"` (`YYYYMMDDTHHMMZ` UTC commit time) from `HEAD`.
- `--reset`: Resets both fields to empty strings `""` (the clean repository state).

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\gen_build_info.ps1 --reset
```

## Coding standards

This project follows the Godot coding standards and philosophy in [docs/coding-standards.md](docs/coding-standards.md).

## License

The source code is licensed under the [MIT License](LICENSE). Compiled distributions and branding are covered by the [End-User License Agreement](EULA.MD).
