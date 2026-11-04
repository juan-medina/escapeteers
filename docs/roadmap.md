# ESCAPETEERS — DEVELOPMENT ROADMAP

This roadmap sequences upcoming gameplay milestones to build on the core pillars in [gdd.md](gdd.md): **Stick-Only Spatial Control**, **The Fellowship Formation**, **Mindful Hazard Navigation**, and **Lock-and-Key Progression**.

---

## Milestone 1: Enemy Roster & Room Composition
**Goal:** Make the 8 hero archetypes (knockback, pinning, cleave, slow, heal) matter by introducing distinct enemy roles and mixed room spawns.
**Estimated Effort:** ~6–8 hours total (~1.5–2 hours per enemy type + spawning rules)

> **Already in Use:**
> - **Heroes (8):** `Archer`, `Armored Axeman`, `Knight`, `Knight Templar`, `Priest`, `Soldier`, `Swordsman`, `Wizard`
> - **Enemies (3):** `Lava Slime` (Hybrid Skirmisher), `Skeleton` (Fast Backline Rusher), `Skeleton Archer` (Ranged Artillery)

1. **[DONE] First Enemy to Build — `Skeleton` (Melee Rusher):**
   - Fast close-combat swarm unit (`80.0` speed, `95.0` HP) that persistently targets healers/ranged heroes and slips through formation gaps when moving.
   - Includes `Attack01`, heavy `Attack02`, and `summon` animation ready for `Necromancer`.
2. **[DONE] Second Enemy — `Skeleton Archer` (Ranged Artillery):**
   - Fires `BoneArrow` projectiles across long range (`155.0` px) in any direction with line of sight, kiting backward between shots when heroes close within `65.0` px.
   - Includes `summon` animation ready for `Necromancer`.
3. **Third Enemy — `Necromancer` (Summoner):**
   - Hangs back and continuously summons `Skeleton` waves until eliminated.
   - Creates high-priority rush-down targets.
4. **Fourth Enemy — `Armored Orc` or `Hellhound` (Tier 2 Threat):**
   - `Hellhound` / `Werewolf` as a high-speed pack rusher, or `Armored Orc` as a high-HP frontline bruiser with knockback resistance.
5. **Tiered Room Spawning & Grouping:**
   - Update `WorldPlan` and `Game` spawning logic to mix enemy types by depth/tier:
     - **Tier 1 (Depth 1):** `Skeleton` + `Lava Slime`
     - **Tier 2 (Depth 2–3):** `Skeleton` + `Skeleton Archer` + `Hellhound` / `Armored Orc`
     - **Tier 3 (Depth 4+):** `Necromancer` guarded by `Skeleton` + `Skeleton Archer` + `Lava Slime`

---

## Milestone 2: Localized Spike Traps
**Goal:** Challenge squad steering in corridors and rooms, keeping navigation tense even when no enemies are present.
**Estimated Effort:** ~2–3 hours

1. **Spike Trap Hazard Scene & Tile Placement:**
   - Place localized floor spike patches in corridor chokepoints, room corners, and around key pedestals.
2. **Trailing Squad Navigation Risk:**
   - Deal damage to any hero or companion stepping on active spikes, rewarding wide turns so the trailing crescent formation does not drag fragile backline units (`Priest`, `Wizard`) across hazards.

---

## Milestone 3: Color-Coded Keys, Doors & Backtrack Ambushes
**Goal:** Add macro-level exploration and route planning across east/west branches while keeping backtracking engaging.
**Estimated Effort:** ~5–7 hours

1. **Color Doors & Keys in `WorldPlan`:**
   - Generate locked color-coded doors (e.g., Yellow, Blue, Red) blocking northward progression or branch sectors, with matching keys placed in accessible lateral rooms.
2. **HUD Key Tracker:**
   - Display collected keys on the HUD and minimap overlay (`MapOverlay`).
3. **Key-Pickup Ambush Waves (Anti-Empty Backtrack):**
   - Picking up a key triggers a fresh ambush quota in selected cleared rooms along the return route, combining with spike traps so backtracking never feels empty.

---

## Milestone 4: Boss Encounters & Run Victory
**Goal:** Provide climactic combat tests and a clear win condition to complete the core game loop.
**Estimated Effort:** ~5–8 hours

1. **Sector Mini-Boss — `Minotaur` or `Greatsword Skeleton` (1.5x Scale):**
   - High-health key guardian with heavy cleave knockback that punishes stationary squads.
2. **Final Boss — `Demon_A` or `Black Knight_A` (1.75x–2x Scale):**
   - Placed in the pinnacle northern chamber (`max_depth` in `WorldPlan`).
   - Combines heavy area melee slams with periodic minion summon waves.
3. **Victory Flow:**
   - Trigger a Run Victory dialog/screen upon defeating the Final Boss (mirroring the `GameOverDialog` flow).

---

## Milestone 5: Combat Readability & Scope Guardrails
**Goal:** Keep large-scale 80-hero vs. 160-enemy battles readable and faithful to the core design.
**Estimated Effort:** ~2–3 hours

1. **Visual & Audio Telegraphs:**
   - Add brief cast/attack telegraphs and sound effects for ranged enemy volleys, summoner waves, and boss slams.
2. **Skill Scope Guardrail (Deferred / Out of Scope):**
   - Avoid passive DoT perks (burning, poison) that only add background numbers.
   - Keep any future skill iterations strictly tied to **spatial control** (knockback, pull, slow, pinning, arc size, formation protection).

