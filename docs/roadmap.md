# ESCAPETEERS — DEVELOPMENT ROADMAP

This roadmap sequences upcoming gameplay milestones in priority order based on playtester feedback and the core pillars in [gdd.md](gdd.md): **Stick-Only Spatial Control**, **The Fellowship Formation**, **Squad Drafting & Class Progression**, **Mindful Hazard Navigation**, and **Lock-and-Key Shortcut Progression**.

---

## Priority 1: Combat Readability (Throttled SFX)
1. **Throttled Combat SFX:**
   - Implement a 3-tier rate-limited sound hierarchy in `Audio` where Tier 1 alerts (companion death, leader hurt, telegraphs, trap triggers) always play clearly, Tier 2 combat impacts (heavy strikes, ranged volleys, enemy deaths) are cooldown-throttled, and Tier 3 background chatter never clutters the mix.

---

## Priority 2: Zelda-Style Key Shortcuts & Locked Doors
**Goal:** Add macro-level exploration and route planning across lateral branches while preventing empty dead-end walkbacks.

1. **Color-Coded Doors & Keys (with VFX/SFX):**
   - Generate locked color-coded doors (e.g., Yellow, Blue, Red) blocking northward progression, with matching keys placed in accessible lateral branches and tracked on the HUD/map overlay.
2. **Zelda-Style Shortcut Loops:**
   - Reaching a Key room opens a shortcut path or gate connecting back toward the locked door room, turning key hunts into forward loops that combine with out-of-combat sprint and spike traps.

---

## Priority 3: Tier 2 Enemy Threat & Boss Encounters
**Goal:** Expand combat variety, test formation knockback/perimeter strength, and provide a climactic win condition (with built-in Telegraphs, VFX, and SFX for each unit).

1. **Tier 2 Threat — `Armored Orc` or `Hellhound`:**
   - `Armored Orc` as a durable frontline bruiser with knockback resistance, or `Hellhound` / `Werewolf` as a high-speed pack rusher.
2. **Sector Mini-Boss — `Minotaur` or `Greatsword Skeleton`:**
   - Enlarged, high-durability key guardian with telegraphed heavy cleave knockback that punishes stationary squads.
3. **Final Boss & Run Victory — `Demon` or `Black Knight`:**
   - Placed in the pinnacle northern chamber combining telegraphed area slams with minion waves, triggering the Run Victory flow upon defeat.

---

## Priority 4: Special Event Rooms (Trap & Wave Mechanics)
**Goal:** Add distinct room-level gameplay mechanics beyond standard enemy quotas using traps, doors, and summoners.

1. **Closing-Spike Perimeter Room:**
   - Upon entry, outer floor spike rings progressively activate inward toward the center until all enemies in the room are cleared.
2. **Lock-In Wave Ambush Room:**
   - Room doors seal shut on entry as Necromancers summon themselves in via pentagrams and raise waves of undead until defeated.

---

## Priority 5: Weighted Recruit & Level-Up Roll Percentages
**Goal:** Nudge mid-run adaptation while preserving specialized build choices.

1. **Diminishing Duplicate Weight in `RecruitPanel`:**
   - Weight recruitment card rolls by inverse owned unit count so unowned or lower-count classes appear more frequently while still allowing duplicates to roll.
2. **Inverse Level Weight in `LevelUpPanel`:**
   - When four or more classes are active in the squad, weight level-up card rolls toward lower-level classes so under-leveled squad roles appear more often.

---

## Scope Guardrails
- **Stick-Only Control:** All room mechanics, traps, and rewards operate purely through movement and positioning—no manual action buttons or RPG inventory menus.
- **Skill Scope Guardrail:** Avoid passive damage-over-time perks (burning, poison) that only add background numbers; keep all combat abilities strictly tied to **spatial control** (knockback, pull, slow, stun, pinning, arc size, formation protection).
