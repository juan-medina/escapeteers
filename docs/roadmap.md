# ESCAPETEERS — DEVELOPMENT ROADMAP

This roadmap sequences upcoming gameplay milestones in priority order based on playtester feedback and the core pillars in [gdd.md](gdd.md): **Stick-Only Spatial Control**, **The Fellowship Formation**, **Squad Drafting & Class Progression**, **Mindful Hazard Navigation**, and **Lock-and-Key Shortcut Progression**.

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

## Priority 1: Stat & Cooldown Scaling Curve (`eval_stat`)
**Goal:** Ensure class level-ups feel rewarding from early to late game without cooldowns reaching zero or flat bonuses feeling stagnant.

1. **Attack-Speed Divisor Cooldown Scaling (`growth < 0`):**
   - Replace linear cooldown subtraction with `base / (1.0 + (level - 1) * abs(growth))` so each level grants a consistent percentage attack rate boost and never reaches `0.0s`.
2. **Compound Stat Scaling (`growth > 0`):**
   - Use soft compound scaling `base * pow(1.0 + growth, level - 1)` for Health and Damage so the `+X` bonus displayed on `UnitCard` grows visibly as players invest deeper into a class.

---

## Priority 2: Out-of-Combat Auto-Sprint
**Goal:** Eliminate slow traversal across cleared rooms and corridors while keeping 100% stick-only control.

1. **Automatic Out-of-Combat Speed Boost:**
   - Increase squad movement speed automatically when no enemies are actively engaged, making backtracking and branch exploration brisk and responsive.

---

## Priority 3: Localized Spike Traps
**Goal:** Turn high-speed out-of-combat sprinting and combat positioning into active spatial dodging.

1. **Spike Trap Hazard Scene & Tile Placement:**
   - Place localized floor spike patches in corridor chokepoints, room corners, and key locations.
2. **Trailing Squad Navigation Risk:**
   - Deal damage to any hero or companion stepping on active spikes, rewarding wide turns (especially while sprinting out of combat) so the trailing crescent formation does not drag fragile backline units across hazards.

---

## Priority 4: Combat Readability (Telegraphs, VFX & Throttled SFX)
**Goal:** Establish *Gauntlet*-style clarity in large horde battles before adding new enemies, bosses, and event rooms, and bundle Telegraphs/VFX/SFX into every subsequent feature.

1. **Combat Telegraphs:**
   - Add clear visual warnings before enemy ranged volleys, Necromancer summons, and spike hazard activations.
2. **Combat & Death VFX:**
   - Add distinct visual feedback for companion deaths, `SquadGridCell` damage/loss alerts, and hero heavy strikes.
3. **Throttled Combat SFX:**
   - Implement a 3-tier rate-limited sound hierarchy in `Audio` where Tier 1 alerts (companion death, leader hurt, telegraphs, trap triggers) always play clearly, Tier 2 combat impacts (heavy strikes, ranged volleys, enemy deaths) are cooldown-throttled, and Tier 3 background chatter never clutters the mix.

---

## Priority 5: Zelda-Style Key Shortcuts & Locked Doors
**Goal:** Add macro-level exploration and route planning across lateral branches while preventing empty dead-end walkbacks.

1. **Color-Coded Doors & Keys (with VFX/SFX):**
   - Generate locked color-coded doors (e.g., Yellow, Blue, Red) blocking northward progression, with matching keys placed in accessible lateral branches and tracked on the HUD/map overlay.
2. **Zelda-Style Shortcut Loops:**
   - Reaching a Key room opens a shortcut path or gate connecting back toward the locked door room, turning key hunts into forward loops that combine with out-of-combat sprint and spike traps.

---

## Priority 6: Tier 2 Enemy Threat & Boss Encounters
**Goal:** Expand combat variety, test formation knockback/perimeter strength, and provide a climactic win condition (with built-in Telegraphs, VFX, and SFX for each unit).

1. **Tier 2 Threat — `Armored Orc` or `Hellhound`:**
   - `Armored Orc` as a durable frontline bruiser with knockback resistance, or `Hellhound` / `Werewolf` as a high-speed pack rusher.
2. **Sector Mini-Boss — `Minotaur` or `Greatsword Skeleton`:**
   - Enlarged, high-durability key guardian with telegraphed heavy cleave knockback that punishes stationary squads.
3. **Final Boss & Run Victory — `Demon` or `Black Knight`:**
   - Placed in the pinnacle northern chamber combining telegraphed area slams with minion waves, triggering the Run Victory flow upon defeat.

---

## Priority 7: Special Event Rooms (Trap & Wave Mechanics)
**Goal:** Add distinct room-level gameplay mechanics beyond standard enemy quotas using traps, doors, and summoners.

1. **Closing-Spike Perimeter Room:**
   - Upon entry, outer floor spike rings progressively activate inward toward the center until all enemies in the room are cleared.
2. **Lock-In Wave Ambush Room:**
   - Room doors seal shut on entry as Necromancers summon themselves in via pentagrams and raise waves of undead until defeated.

---

## Priority 8: Weighted Recruit & Level-Up Roll Percentages
**Goal:** Nudge mid-run adaptation while preserving specialized build choices.

1. **Diminishing Duplicate Weight in `RecruitPanel`:**
   - Weight recruitment card rolls by inverse owned unit count so unowned or lower-count classes appear more frequently while still allowing duplicates to roll.
2. **Inverse Level Weight in `LevelUpPanel`:**
   - When four or more classes are active in the squad, weight level-up card rolls toward lower-level classes so under-leveled squad roles appear more often.

---

## Scope Guardrails
- **Stick-Only Control:** All room mechanics, traps, and rewards operate purely through movement and positioning—no manual action buttons or RPG inventory menus.
- **Skill Scope Guardrail:** Avoid passive damage-over-time perks (burning, poison) that only add background numbers; keep all combat abilities strictly tied to **spatial control** (knockback, pull, slow, stun, pinning, arc size, formation protection).
