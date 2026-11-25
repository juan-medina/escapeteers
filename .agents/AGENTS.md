# Agent guidelines for Kaze no Michi

## Start here

- **Read the GDD first:** `docs/gdd.md` for the project context before starting.
- **Coding standards & philosophy:** follow `docs/coding-standards.md` — typing, formatting,
  naming, architecture, error handling. Those rules apply to all GDScript in this repo.
- **Enforce standards during refactors:** Flag and fix `.tscn` violations (static UI built with `.new()`/`queue_free()`, re-skinned generic cards instead of pre-instanced static cards, or procedural `_draw()` UI/backgrounds, manual particle arrays, and runtime `SpriteFrames` setup instead of native `.tscn` nodes like `ColorRect`, `ProgressBar`, `CPUParticles2D`, and `AnimatedSprite2D`) and strip inherited defensive `if` checks on guaranteed nodes, assets, or data so build bugs fail fast.
- **Formatting, Linting & Type Safety:** Follow `docs/coding-standards.md` Section 3. Always run the mandatory 3-step verification on modified GDScript files by running: `powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1 <file>...` (this script handles `gdformat -l 150`, `gdlint`, and headless `godot --check-only` with isolated cache paths to avoid Windows AppData access errors). Ensure zero Godot compiler warnings remain before submitting. Never chain other commands (such as `autoplay.ps1`, `git` commands, or multi-step scripts) onto `verify.ps1`—always invoke `verify.ps1` and `autoplay.ps1` as separate standalone commands.
- **Running Godot & Custom Scripts:** Custom scripts are not forbidden, but remember this is a Godot 4 project with `[autoload]` singletons—standalone scripts run directly via `godot -s` may fail to compile against autoloads or hang headlessly without exiting (and require isolated Windows cache paths). Whenever the goal is to verify code or run autoplay/balance checks, use our existing PowerShell script wrappers (`scripts/verify.ps1` and `scripts/autoplay.ps1`) instead of inventing ad-hoc runners.
- **Autoload Architecture & Global UI:**
  - **No class_name on Singletons:** Never add `class_name` to autoload singleton scripts in this project (e.g., `alerts.gd`, `transition.gd`). Autoloads are registered as singletons in `project.godot`; adding `class_name` causes global namespace collisions.
  - **Facade Managers:** Do not add generic UI scenes (like `Toast` or `ConnectingOverlay`) as standalone Autoloads. Instead, group them under a single Facade Manager Autoload (like `Alerts`).
  - **Instantiating & Casting:** The Manager Autoload should instantiate its managed UI scenes and strictly cast them to their `class_name` once inside its `_ready()` function.
  - **Semantic API:** The Manager should expose simple semantic methods for the rest of the game to use. Callers should interact with the Manager's API and never need to cast or access the underlying UI nodes directly.
- **Scope & Restraint (Strict):** Never overextend the scope of what the user asks. Never implement, wire up, or 'tidy up' unasked systems (e.g., adding damage logic, health reductions, death states, or cleanup routines ahead of time). If you find unhandled stubs or related work, ask the user first instead of implementing them on your own.
- **Coroutines & Await:** In Godot 4, calling a coroutine without `await` triggers a `MISSING_AWAIT` warning, which fails our strict warning checks. Crucially, `Alerts.fatal_error()` and `Alerts.quit_game()` are coroutines. Always call them with `await` (e.g., `await Alerts.fatal_error(...)`).
- **Changelog Updates:** Every time you work on a player-visible feature, the final step is to update `src/changelog_panel/changelog.txt` under the current WIP version section, maintaining its BBCode formatting style:
  - **Player-Facing & Fun:** Write for players in a light, arcade tone. Omit internal refactors, asset pack names, code details, formulas, and technical numbers.
  - **Ultra-Short (4–8 Words):** Keep descriptions to a 4–8 word punchy phrase after the bold title. Never add "so that..." explanations or laundry lists of sub-details.
  - **Consolidate WIP Changes:** If tweaking or fixing a feature that was introduced in the same `WIP` version, update its existing bullet instead of adding separate `Changed` or `Fixed` entries.
  - **Format:** `- [color=#ffffff][b]Short Title:[/b][/color] Fun 4-8 word summary.` under the appropriate section (`Added`, `Changed`, `Fixed`).


## GitHub Issues
When instructed to review, edit, or modify GitHub issues (e.g., reviewing a specific issue number), use the GitHub CLI tool (`gh`) directly instead of manually querying the GitHub API or scraping web pages (e.g., `gh issue view <number>`, `gh issue edit <number>`, `gh issue comment <number>`).

- **Parent Release Issues:** Group releases under parent tracking issues titled `Release vX.Y.Z: <Summary>` and tagged with the `release` label (`gh issue list --label release`).
- **Ordered Sub-Issues:** List each release's issues as an ordered checklist (`1. - [ ] #<number>`) under `## Implementation Order` in the parent issue, and link them as native GitHub Sub-issues in that exact execution order (`gh api repos/:owner/:repo/issues/<parent_number>/sub_issues -X POST -F sub_issue_id=<issue_database_id>`).
- **Priority & Execution Order:** Work release-by-release (lowest open `Release vX.Y.Z` parent first) and top-to-bottom through its sub-issues (`gh api repos/:owner/:repo/issues/<parent_number>/sub_issues`). When adding new issues to the roadmap, attach them to the appropriate `Release vX.Y.Z` parent issue in implementation order.


## Git Commit Rules
When generating git commit messages, strictly follow these constraints:
- Must be exactly 1 line (no multi-line body or bullet points).
- Must start with a lowercase letter.
- Maximum length is 150 characters.
- Do NOT use Conventional Commits prefixes (e.g., do not use `feat:`, `fix:`, `feat(scope):`).
- Keep it concise, descriptive, and focused on the key change.
- When working on a GitHub issue, reference the issue number at the end of the commit message with a single hash (e.g., `refactor level up and recruit panels #7`).