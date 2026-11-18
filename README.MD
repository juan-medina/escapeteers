# Escapeteers
[![License: MIT](https://img.shields.io/badge/License-MIT-478CBF.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Conduct](https://img.shields.io/badge/Conduct-Covenant%202.0-478CBF.svg?style=for-the-badge)](https://www.contributor-covenant.org/version/2/0/code_of_conduct/)
[![Made with Godot](https://img.shields.io/badge/GODOT-4.7-478CBF?style=for-the-badge&logo=godot%20engine&logoColor=white)](https://godotengine.org)

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

### Fonts

#### m5x7
* **Author:** [Daniel Linssen](https://managore.itch.io/)
* **Source:** [Itch.io](https://managore.itch.io/m5x7)
* **License:** Free for personal and commercial use.

---

## Autoplay, Profiling & Balance Testing

Run the zero-overhead autoplay suite (`src/autoplay/`, excluded from release exports) via PowerShell to hunt CPU performance hiccups headlessly, sweep build/class balance, or watch live replays:

### Modes

| Mode | Purpose | Defaults |
| :--- | :--- | :--- |
| `perf` | Headless CPU profiler (subsystem timers + top 20 slowest frames) | `3` seeds, immortal leader, `1x` speed, `9000` frames (`150s`) |
| `balance` | Headless single-build mortality & DPS/room-difficulty audit | `20` seeds, real death, `1x` speed (`60Hz` uncapped), `18000` frames (`300s`) |
| `matrix` | Headless sweep comparing all builds (`balanced`, `melee_stack`, `ranged_kite`, `random`, and `mono:<hero>`) | `10` seeds per build, `1x` speed (`60Hz` uncapped) |
| `watch` | Windowed live replay with rendering and audio enabled | `1` seed, `2x` speed |

### Parameters

- `-Mode <perf|balance|matrix|watch>`: Runner mode (default `perf`).
- `-Build <balanced|melee_stack|ranged_kite|random|mono:<hero_id>>`: Draft & level-up policy (default `balanced`).
- `-Leader <hero_id>`: Starting hero class (default `knight`).
- `-Seeds <int>` / `-Seed <int>`: Number of sequential seeds and/or fixed starting seed (default `12345`).
- `-MaxDepth <int>`, `-MaxFrames <int>`, `-Speed <float>`, `-Out <path.json>`: Depth cap, frame cap, time scale, and optional JSON export.

### Examples

```powershell
# Profile 3 seeds headlessly for performance hiccups
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode perf -Seeds 3

# Test a single build's balance across 20 seeds
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode balance -Leader knight -Build melee_stack -Seeds 20

# Compare all builds and hero classes, exporting full JSON telemetry
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode matrix -Seeds 10 -Out .venv\cache\balance_matrix.json

# Watch the bot play seed 12345 in a visible window at 2x speed
powershell -ExecutionPolicy Bypass -File .\scripts\autoplay.ps1 -Mode watch -Seed 12345 -Build balanced -Speed 2
```

## Coding standards

This project follows the Godot coding standards and philosophy in [docs/coding-standards.md](docs/coding-standards.md).

## License

The source code is licensed under the [MIT License](LICENSE). Compiled distributions and branding are covered by the [End-User License Agreement](EULA.MD).
