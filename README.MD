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

#### 16-Bit Fantasy: Battles Music Pack
* **Author:** [Marllon Silva (xDeviruchi)](https://xdeviruchi.itch.io/)
* **Source:** [Itch.io](https://xdeviruchi.itch.io/16-bit-fantasy-battles-music-pack)
* **License:** Paid. Used under a purchased license (personal and commercial
  use allowed; minor edits allowed; redistribution, resale, and OST releases
  prohibited). Attribution optional but appreciated.

### Sound Effects

#### Modern UI SFX
* **Author:** [Leohpaz](https://www.patreon.com/cw/leohpaz)
* **Source:** [Itch.io](https://leohpaz.itch.io/modern-ui-sfx)
* **License:** Paid. Used under a purchased license (personal and commercial use allowed; the pack may not be resold or redistributed).

### Fonts

#### m5x7
* **Author:** [Daniel Linssen](https://managore.itch.io/)
* **Source:** [Itch.io](https://managore.itch.io/m5x7)
* **License:** Free for personal and commercial use.

---

## Coding standards

This project follows the Godot coding standards and philosophy in [docs/coding-standards.md](docs/coding-standards.md).

## License

The source code is licensed under the [MIT License](LICENSE). Compiled distributions and branding are covered by the [End-User License Agreement](EULA.MD).
