# Godot Coding Standards & Philosophy

Welcome to the project! This document outlines the coding conventions and philosophy we follow. Please review these guidelines before contributing to ensure consistency and maintainability across the codebase.

## 1. Guiding Philosophy

- **Understand code before you change it.** Take a moment to read the surrounding code and understand its context before making modifications.
- **Keep it simple (YAGNI).** Add abstractions or manager nodes only when there is a concrete need for them. Start simple and refactor when necessary.
- **Write meaningful comments.** Code should strive to be self-documenting through clear naming. Use comments to explain the *why*—such as external constraints, invariants, or complex logic—rather than the *what*.
- **Keep changes focused.** Try to keep your pull requests focused on a single feature or bug fix. Avoid reformatting or refactoring code outside the scope of your current task.
- **Respect established conventions.** Follow the existing patterns in the codebase. If you see an established way of doing things (like our asset split or import settings), try to stick to it unless there's a strong reason to change it.

## 2. Project Configuration & Typing

- **Strict static typing.** We use GDScript 2.0 static typing everywhere.
- **Explicit typing.** Always use explicit type hints (e.g., `var tween: Tween = create_tween()`); please do not rely solely on type inference (`:=`).
- **Treat warnings as errors.** Please ensure all Godot warnings are addressed before submitting your code. Verify zero warnings using Godot's built-in static analyzer: `godot --headless --path src --check-only -d -s <file>`. Note that `gdlint` only checks style; only Godot with `-d` (`--debug`) checks GDScript static type errors, unsafe method access, unsafe casts, and integer division.
- **Avoid lambdas:** Implement them as static functions (if they don't require instance data) or normal functions (if they require instance data) to improve readability and maintainability.

## 3. Formatting & Linting

- **Indentation:** Use **tabs**.
- **Line endings:** Use **LF**.
- **Blank lines:** Use **two** blank lines between functions.
- **Quotation marks:** Use double quotes `""` by default.
- **StringName for constants:** For literal strings that are never modified (like log/UI messages, keys, action, and group names), use `&"..."` instead of `"..."`. Be consistent within a statement.
- **Line length: 150 characters max.** This is enforced by `.gdlintrc` and `gdformat`. If a line is too long, try extracting a named local variable or splitting it into two statements. Avoid hand-wrapping, as `gdformat` will just rejoin it.
- **Declaration order:** We follow the `.gdlintrc` `class-definitions-order`: `signals → enums → consts → static vars → exports → public vars → private vars → @onready vars → methods`.
- **Lint, format & type safety (The Boy Scout Rule).** Before finishing your work, please run:
  1. `gdformat -l 150 <file>` (code formatting)
  2. `gdlint <file>` (style linting)
  3. `godot --headless --path src --check-only -d -s <file>` (static type analysis)
  Note that `gdlint` automatically reads our 150-character limit from `.gdlintrc`, but the standalone `gdformat` CLI defaults to 100 characters unless you pass `-l 150` (VS Code handles this automatically via the formatter extension). If you notice any pre-existing formatting or linting issues in a file you're editing, please fix those as well while you're there—leave the code better than you found it!

## 4. Naming

- **Classes / nodes (file names):** `PascalCase`
- **Variables, parameters, functions:** `snake_case`
- **Constants:** `CONSTANT_CASE`
- **Private variables / functions:** `_snake_case`
- **Signals:** `snake_case`

## 5. Architecture & Communication

- **Call down, signal up.** Parents should call their children directly; children should emit signals for parents to listen to.
- **Connect UI signals in the editor.** For UI components that exist in a scene (`.tscn`), connect their signals (like `pressed`, `focus_entered`, etc.) using the Godot editor's Node panel rather than connecting them via code in `_ready()`. This keeps the visual hierarchy and its connections explicitly tied together in the scene file and avoids duplicate connection errors.
- **Avoid `get_node("../")` or `get_parent()`.**
- **Dependency injection via exports.** Expose dependencies as `@export` variables to keep nodes decoupled.
- **Menu navigation:** `PanelHost.show_panel` and `Transition._go_to_scene` call `get_viewport().gui_release_focus()` when navigation commits. This prevents doubled inputs during transitions. Please preserve these calls.

## 6. Performance & Memory

- Avoid allocating new objects inside `_process` loops.
- Cache node references in `_ready()` using `@onready`. Avoid calling `get_node()` inside process loops.
- Use `queue_free()` instead of `free()`.

## 7. Scene & Folder Structure

- **Scene-based organization.** Group `.tscn` and `.gd` files by feature (e.g., `src/player/player.tscn`).
- **Asset splitting:** Binary assets live under `src/data/assets/`. Please see the data folder's README for more details.
- **Moving files:** Moving files on disk (outside of Godot) can stale the editor cache. If you see `Cannot open file res://…` errors, simply close Godot, delete `src/.godot/`, and reopen to force a reimport.

## 8. Error Handling & Termination

### 1. Developer Errors: Fail Fast in Development
- **Never swallow developer mistakes.** If a bundled scene fails to instantiate, a required node is missing, or a required export is unassigned, this is a build-time bug.
- **Do not write defensive boilerplate.** Avoid wrapping internal node references or `preload().instantiate()` in `if x != null`, returning `null`, or falling back to default dummy values (e.g., returning `false` or `Vector2.ZERO`).
- **Let the engine crash loudly.** An immediate engine error or null dereference in development points directly to the broken scene or line so it can be fixed before shipping.

### 2. External Failures: Graceful Termination (`Alerts.fatal_error`)
- **App termination:** All intentional app termination must go through the `Alerts` autoload. Never call `get_tree().quit()` directly.
  - For user exits (e.g. Exit button): `await Alerts.quit_game()`.
  - For unrecoverable external failures: `await Alerts.fatal_error(&"Short user message")`.
- `Alerts` handles the entire termination experience, including audio fading and the error dialog, while delegating the visual fade to `Transition`. Because it waits for these animations to finish, these methods act as coroutines. Please remember to use the `await` keyword to prevent `MISSING_AWAIT` linter warnings!
- **Reserve fatal errors for external I/O:** Use `fatal_error` exclusively for conditions that can legitimately fail in production outside our control (e.g. corrupted save data on disk, missing filesystem resources).
- **Pattern:**
  ```gdscript
  if not file:
      printerr(&"Could not open config file: " + config_path + &"!")
      await Alerts.fatal_error(&"Could not load game data")
      return
  ```
  - Log technical details with `printerr`.
  - Provide a short, player-friendly message to `fatal_error`.
  - Include a trailing `return` to safely unwind the function.

### 3. Gameplay State Variability: Normal Branching
- Only branch or return early (`if target == null: return`) when null is a valid, expected state in the game loop (e.g. lost line of sight, entity died, no active leader).

## 9. Autoloads & Global UI

- **Global Systems Architecture Taxonomy:**
  1. **Scene Autoloads (`Node` or `.tscn`):** For systems requiring the Godot lifecycle (`_process`, `_input`), holding spawned child nodes, or existing outside scene transitions (e.g., `Audio`, `Transition`, `Crt`).
  2. **Facade Manager Autoloads (`Node`):** For global UI overlays that manage complex, generic UI scenes without polluting the root namespace (e.g., `Alerts` managing `Toast` and `ConnectingOverlay`).
  3. **Static Utilities (`class_name` with `static func`):** For pure, stateless data parsing or processing that does not require being in the SceneTree (e.g., `BuildInfo`, `BadWordFilter`). Pure stateless utility scripts must not be Autoload Nodes.
- **No class_name for Autoloads:** Never add `class_name` to autoload singleton scripts (e.g. `alerts.gd`, `transition.gd`). Autoloads are registered as singletons in `project.godot`; adding `class_name` causes global namespace collisions.
- **Facade Managers for Global UI:** Do not add individual UI components (such as `Toast`, `ConnectingOverlay`, or `ErrorDialog`) as their own standalone Autoloads. Instead, group them under a single Facade Manager (like `Alerts`).
- **Instantiating Overlays & Type Safety:** The Manager Autoload should preload the `PackedScene` for its UI elements, instantiate them, and strictly cast them to their custom type once in its `_ready()` function (e.g., `_toast = TOAST_SCENE.instantiate() as ToastScene`). By centralizing the instantiation and the cast inside the manager, the rest of the codebase can interact with global UI safely without ever needing to cast nodes or worry about the underlying hierarchy.
- **Semantic API:** The rest of the game should never manipulate global UI nodes directly. The Manager should expose clear, semantic methods (e.g., `Alerts.controller_detected()`, `Alerts.show_epic_login_overlay()`) that internally control the UI.
- **Process Mode:** UI nodes added as children of an Autoload will inherit its `process_mode`. For instance, if the manager is set to `Node.PROCESS_MODE_ALWAYS`, its child dialogs will continue to animate and function even when `get_tree().paused = true`.
