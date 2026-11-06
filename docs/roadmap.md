# ESCAPETEERS — DEVELOPMENT ROADMAP

This roadmap sequences upcoming gameplay milestones to build on the core pillars in [gdd.md](gdd.md): **Stick-Only Spatial Control**, **The Fellowship Formation**, **Squad Drafting & Class Progression**, **Mindful Hazard Navigation**, and **Lock-and-Key Progression**.

---

## Completed Foundation: Squad Progression, HUD & Core Enemy Roster
- **[DONE] Hero Selection, Recruitment Drafting & Class Leveling:**
  - Starting hero selection before entering the dungeon.
  - Card-based recruitment drafting when rescuing mystery survivors, including early healer availability protection.
  - Squad experience progression and class level-up choices that upgrade all active and future units of the chosen hero class.
- **[DONE] Tactical HUD & Map Overlay:**
  - Live squad health grid, per-class encounter DPS meter, XP progress bar, and toggleable dungeon map overlay showing explored vs. revealed frontier areas.
- **[DONE] Core Enemy Archetypes:**
  - **Lava Slime (Hybrid Skirmisher):** Close-range melee and horizontally aligned ranged lava projectiles.
  - **Skeleton (Melee Rusher):** Fast close-combat swarm unit with light and heavy strikes that prioritizes healers and ranged backline heroes.
  - **Skeleton Archer (Ranged Artillery):** Long-range archer that fires in any direction with line of sight and kites away when heroes close in.
  - **Necromancer (Summoner):** Backline caster that kites away from threats and periodically places summoning circles to raise undead melee and archer minions.
- **[DONE] Themed Room Archetypes & Encounter Spawning:**
  - Rooms receive distinct encounter archetypes (`Slime Pit`, `Bone Swarm`, `Archer Garrison`, and deeper `Necromancer Crypt` chambers) with graph coloring so adjacent rooms vary their tactical identity.

---

## Milestone 1: Tier 2 Enemy Threat
**Goal:** Complete the enemy roster with a durable frontline bruiser or fast pack hunter to test knockback and formation perimeter strength.

1. **Tier 2 Threat — `Armored Orc` or `Hellhound`:**
   - `Hellhound` / `Werewolf` as a high-speed pack rusher, or `Armored Orc` as a durable frontline bruiser with knockback resistance.

---

## Milestone 2: Localized Spike Traps
**Goal:** Challenge squad steering in corridors and rooms, keeping navigation tense even when no enemies are present.

1. **Spike Trap Hazard Scene & Tile Placement:**
   - Place localized floor spike patches in corridor chokepoints, room corners, and around key pedestals.
2. **Trailing Squad Navigation Risk:**
   - Deal damage to any hero or companion stepping on active spikes, rewarding wide turns so the trailing crescent formation does not drag fragile backline units across hazards.

---

## Milestone 3: Color-Coded Keys, Doors & Backtrack Ambushes
**Goal:** Add macro-level exploration and route planning across east/west branches while keeping backtracking engaging.

1. **Color Doors & Keys:**
   - Generate locked color-coded doors (e.g., Yellow, Blue, Red) blocking northward progression or branch sectors, with matching keys placed in accessible lateral rooms.
2. **HUD Key Tracker:**
   - Display collected keys on the HUD and dungeon map overlay.
3. **Key-Pickup Ambush Waves (Anti-Empty Backtrack):**
   - Picking up a key triggers a fresh ambush quota in selected cleared rooms along the return route, combining with spike traps so backtracking never feels empty.

---

## Milestone 4: Boss Encounters & Run Victory
**Goal:** Provide climactic combat tests and a clear win condition to complete the core game loop.

1. **Sector Mini-Boss — `Minotaur` or `Greatsword Skeleton`:**
   - Enlarged, high-durability key guardian with heavy cleave knockback that punishes stationary squads.
2. **Final Boss — `Demon` or `Black Knight`:**
   - Placed in the pinnacle northern chamber of the dungeon.
   - Combines heavy area melee slams with periodic minion summon waves.
3. **Victory Flow:**
   - Trigger a Run Victory dialog/screen upon defeating the Final Boss (mirroring the game-over flow).

---

## Milestone 5: Combat Readability & Scope Guardrails
**Goal:** Keep large-scale horde battles readable and faithful to the core design.

1. **Visual & Audio Telegraphs:**
   - Add brief cast/attack telegraphs and sound effects for ranged enemy volleys, summoner waves, and boss slams.
2. **Skill Scope Guardrail (Deferred / Out of Scope):**
   - Avoid passive damage-over-time perks (burning, poison) that only add background numbers.
   - Keep any future skill iterations strictly tied to **spatial control** (knockback, pull, slow, stun, pinning, arc size, formation protection).


