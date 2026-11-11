# Agent guidelines for Kaze no Michi

## Start here

- **Read the GDD first:** `docs/gdd.md` for the project context before starting.
- **Coding standards & philosophy:** follow `docs/coding-standards.md` — typing, formatting,
  naming, architecture, error handling. Those rules apply to all GDScript in this repo.
- **Formatting, Linting & Type Safety:** Follow `docs/coding-standards.md` Section 3. Always run the mandatory 3-step verification on modified GDScript files by running: `powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1 <file>...` (this script handles `gdformat -l 150`, `gdlint`, and headless `godot --check-only` with isolated cache paths to avoid Windows AppData access errors). Ensure zero Godot compiler warnings remain before submitting.
- **Autoload Architecture & Global UI:**
  - **No class_name on Singletons:** Never add `class_name` to autoload singleton scripts in this project (e.g., `alerts.gd`, `transition.gd`). Autoloads are registered as singletons in `project.godot`; adding `class_name` causes global namespace collisions.
  - **Facade Managers:** Do not add generic UI scenes (like `Toast` or `ConnectingOverlay`) as standalone Autoloads. Instead, group them under a single Facade Manager Autoload (like `Alerts`).
  - **Instantiating & Casting:** The Manager Autoload should instantiate its managed UI scenes and strictly cast them to their `class_name` once inside its `_ready()` function.
  - **Semantic API:** The Manager should expose simple semantic methods for the rest of the game to use. Callers should interact with the Manager's API and never need to cast or access the underlying UI nodes directly.
- **Scope & Restraint (Strict):** Never overextend the scope of what the user asks. Never implement, wire up, or 'tidy up' unasked systems (e.g., adding damage logic, health reductions, death states, or cleanup routines ahead of time). If you find unhandled stubs or related work, ask the user first instead of implementing them on your own.
- **Coroutines & Await:** In Godot 4, calling a coroutine without `await` triggers a `MISSING_AWAIT` warning, which fails our strict warning checks. Crucially, `Alerts.fatal_error()` and `Alerts.quit_game()` are coroutines. Always call them with `await` (e.g., `await Alerts.fatal_error(...)`).
- **Changelog Updates:** Every time you work on a feature, the final step is to update `src/changelog_panel/changelog.txt` under the current WIP version section, maintaining its BBCode formatting style:
  - **Player-Facing Only:** Write for players, not developers. Focus on what changed in gameplay or visuals; omit internal code details, formulas, parameter names, and technical FPS/math numbers.
  - **Concise & Punchy:** Exactly one short, clear sentence per bullet point. Avoid over-explaining.
  - **Format:** `- [color=#ffffff][b]Feature Name:[/b][/color] Concise description of the user-visible change.` under the appropriate section (`Added`, `Changed`, `Fixed`).


## Git Commit Rules
When generating git commit messages, strictly follow these constraints:
- Must be exactly 1 line (no multi-line body or bullet points).
- Must start with a lowercase letter.
- Maximum length is 150 characters.
- Do NOT use Conventional Commits prefixes (e.g., do not use `feat:`, `fix:`, `feat(scope):`).
- Keep it concise, descriptive, and focused on the key change.