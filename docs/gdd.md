# GAME DESIGN DOCUMENT: ESCAPETEERS

**Working Title:** Escapeteers  
**Genre:** Top-Down Squad Dungeon Crawler / Horde Survival  
**Target Platform:** PC  
**Inspiration:** Cannon Fodder (Squad movement & attrition), Gauntlet (Dungeon rooms & key-door progression), Vampire Survivors (Zero-button auto-combat)  

---

## 1. High Concept
Lead an auto-battling fellowship of survivors through a room-based dungeon. Choose your starting leader, steer your growing party through corridors and themed encounter chambers, draft new heroes and level up hero classes to expand your squad's firepower, navigate past localized spike hazards, eliminate diverse enemy threats including persistent summoners, and hunt down color-coded keys in distant rooms to unlock matching doors and advance.

---

## 2. Core Design Pillars
- **The Fellowship Formation:** Your squad surrounds you in layered rings. Standing still forms a protective circle around you; walking parts the allies ahead and causes the group to flow around your flanks and rear in a trailing crescent.
- **Stick-Only Spatial Control:** No manual combat or stance buttons. All shooting, melee strikes, and healing trigger automatically based on proximity and cooldowns. When out of combat, the squad automatically sprints at elevated speed to keep exploration brisk. Gameplay focuses on spatial navigation: closing distance for melee units, keeping ranged units in line of sight, and steering trailing companions away from hazards.
- **Squad Drafting & Class Progression:** Rescue mystery survivors waiting in dungeon rooms to draft a new hero from a choice of candidates (weighted to favor under-represented classes in your squad). Defeating enemies awards squad experience; leveling up lets you upgrade an active hero class (weighted toward lower-level classes when holding four or more classes), boosting the stats of all current and future squad members of that class with compound stat growth and diminishing-return cooldown reduction.
- **Color-Coded Key, Door & Shortcut Progression:** Advancement requires exploring lateral branches to find color-coded keys that unlock matching doors blocking deeper dungeon sections, opening Zelda-style shortcut loops back toward the gated main path.
- **Mindful Hazard Navigation & Special Event Rooms:** Localized spike trap patches punish careless steering—especially while sprinting out of combat—requiring wide turns so trailing followers do not drag across hazard zones. Special event chambers up the ante with closing spike perimeters or lock-in wave ambushes.

---

## 3. World & Level Design
The dungeon is procedurally generated as an ascending labyrinth of interconnected rooms and corridors structured around directional progression, exploration, and lock-and-key advancement:

- **Ascending Northward Progression:** The party begins at the southern base of the dungeon in a compact starting chamber scaled to an initial small squad. Pushing northward ascends deeper into the labyrinth where enemy level, encounter quotas, and chamber scale grow to accommodate larger horde battles, while lateral east and west branches offer side routes for recruitment and exploration.
- **Themed Room Encounters & Special Event Chambers:** Each room is assigned an encounter archetype (such as slime pits, undead swarms, archer garrisons, or necromancer crypts) so chambers present distinct tactical challenges upon entry, while preventing adjacent rooms from repeating the same theme. Special event chambers introduce dynamic spatial pressure, including **Closing-Spike Rooms** (where outer spike rings close inward until the enemy quota is cleared) and **Lock-In Wave Ambush Rooms** (where doors seal and Necromancers materialize via pentagrams to summon waves of undead).
- **Rooms, Corridors & Out-of-Combat Sprint:** Corridors funnel the party into tight formations, while chambers provide space for tactical repositioning, companion recruitment, and skirmishes. When no enemies are engaged, the squad automatically sprints to keep traversal fast while turning localized floor traps into high-speed navigation hazards.
- **Atmospheric Dungeon Lighting:** Wall-mounted torches along corridors and free-standing candle posts distributed across room interiors carve warm pools of visibility out of the surrounding darkness, balancing moody shadow contrast with clear combat readability.
- **Color-Coded Doors, Keys & Zelda-Style Shortcuts:** Locked doors (e.g. Red, Blue, Yellow) block passage to subsequent dungeon sectors. Matching keys are hidden in lateral branches; reaching a key room opens a shortcut path or gate leading back toward the locked door room so exploration flows into forward loops rather than empty dead-end walkbacks.
- **Localized Spike Trap Areas:** Floor spikes placed in select areas (corridor chokepoints, room corners, or guarding key locations). Passing over active spikes deals damage to any squad member who steps on them. Spikes are placed sparingly rather than everywhere.

---

## 4. The Squad (The Escapeteers)
Before entering the dungeon, the player selects a starting hero class to act as the lead character and focal point of the fellowship. Companions are discovered as unrecruited mystery survivors waiting in the starting chamber and throughout dungeon rooms; making physical contact opens a recruitment choice where the player drafts one hero from a set of random candidates (with early protection to ensure a healer is offered near the start of a run, and diminishing roll weights for heavily stacked classes so unowned or lower-count classes appear more frequently).

### Progression & HUD Readability
- **Squad Experience, Weighted Rolls & Stat Scaling:** Defeating enemies grants experience toward the overall squad level. Each level-up presents a choice of classes currently represented in the squad (weighted toward lower-level classes when four or more classes are active). Upgrading a class advances its level, restoring existing members of that class to full health, scaling health and damage via a compound growth curve, and reducing ability cooldowns via an attack-speed divisor formula (`base / (1.0 + (level - 1) * rate)`) so attack speed scales smoothly without ever reaching zero cooldown.
- **Tactical HUD, Telegraphs & Throttled Horde Audio:** The interface provides a live squad health grid, an encounter damage-per-second meter broken down by hero class, an experience tracker, and a toggleable dungeon map overlay that distinguishes explored rooms from revealed frontier chambers. To maintain *Gauntlet*-style clarity in large horde battles, combat feedback is split into clear visual telegraphs (enemy volleys, summoner circles, traps), impactful combat/death VFX, and a 3-tier throttled SFX hierarchy where critical alerts (companion deaths, telegraphs, trap triggers) always cut through while repetitive auto-attacks are rate-limited.

### Formation & Engagement Behaviors
- **Multi-Ring Inner Support & Auto-Rotate Frontline:** Companions distribute across concentric formation rings based on role and squad size. Fragile healers and ranged heroes prioritize the innermost rings closest to the leader and anchor in the rear arc. Melee brawlers take outer rings and the forward arc, forming an outward-facing perimeter shield that rotates with the leader's facing and movement direction. During movement, frontline units maintain their forward screen while backline companions flow into a trailing crescent.
- **Melee Leashing & Arc Strikes:** Melee fighters watch a leash range around their formation slot. When enemies are detected, they step forward to strike targets within their forward attack range, returning to formation when targets die or the leader pulls away.
- **Formation Anchors:** Pure ranged attackers and healers stay strictly locked to their formation positions, never breaking ranks to chase.
- **Navmesh Steering:** Companions steer along navmesh paths around walls and obstacles, maintaining line of sight to targets.

### Hero Archetypes & Skills

#### 1. Archer (Ranged Physical)
- **Role:** Long-range single-target sniper.
- **Abilities:**
  - *Snipe Arrow:* Fires swift arrows at distant targets across long range on a moderate cooldown, inflicting heavy knockback on hit to push advancing enemies away from the squad.
- **Positioning:** Stays strictly anchored in formation; requires clear line of sight.

#### 2. Armored Axeman (Melee Brawler)
- **Role:** Frontline brawler and crowd disruptor.
- **Abilities:**
  - *Axe Chop:* Rapid melee slashes on a short cooldown with moderate knockback.
  - *Whirlwind Cleave (Heavy Strike):* Has a chance on attack to unleash a sweeping heavy chop on a longer cooldown, delivering high burst damage and heavy knockback.
- **Positioning:** Steps out on a melee leash to intercept nearby threats.

#### 3. Knight (Melee Vanguard)
- **Role:** Frontline anchor and crowd control pin.
- **Abilities:**
  - *Sword Strike:* Fast melee slashes on a short cooldown with no knockback, pinning enemies in place for squad focus fire.
  - *Heavy Swing (Heavy Strike):* Has a chance on attack to deliver a heavy blow on a longer cooldown, dealing high burst damage and strong knockback.
- **Positioning:** Steps out on a melee leash to lock down advancing targets.

#### 4. Knight Templar (Melee Shock Infantry)
- **Role:** Aggressive frontline defender with high-impact displacement.
- **Abilities:**
  - *Pike Thrust:* Powerful melee thrusts on a short cooldown with strong standard knockback, consistently shoving enemies away.
  - *Heavy Smite (Heavy Strike):* Has a chance on attack to unleash an empowered strike on a longer cooldown with heavy damage and knockback.
- **Positioning:** Steps out on a melee leash to create space for backline allies.

#### 5. Priest (Support Healer & Crowd Control)
- **Role:** Dedicated squad triage, sustain, and disruption.
- **Abilities:**
  - *Divine Heal:* Prioritizes critically injured allies during combat (and tops off injured allies out of combat), channeling healing magic at range on a moderate cooldown.
  - *Holy Smite:* When no urgent triage healing is needed, calls down holy magic on an enemy at range to deal light damage and stun the target.
- **Positioning:** Stays protected within the core of the formation.

#### 6. Soldier (Hybrid Melee / Ranged)
- **Role:** Adaptive combatant adjusting to target distance.
- **Abilities:**
  - *Arrow Shot:* Fires ranged arrows on a short cooldown while enemies remain at distance.
  - *Sword Slash:* Draws a blade and steps out on a melee leash when enemies close in, delivering fast melee slashes with no knockback.
- **Positioning:** Dynamically transitions between formation archery and leash-based melee combat.

#### 7. Swordsman (Melee Skirmisher)
- **Role:** Rapid-strike duelist specializing in multi-hit damage.
- **Abilities:**
  - *Quick Slash:* Fast sword slices on a short cooldown with no knockback to maintain pressure.
  - *Blade Flurry (Heavy Strike):* Has a chance on attack to trigger a multi-hit flurry on a longer cooldown, striking multiple times in rapid succession for heavy compound damage without pushing the target away.
- **Positioning:** Steps out on a melee leash to shred priority targets.

#### 8. Wizard (Ranged Crowd Control)
- **Role:** Spellcaster and crowd decelerator.
- **Abilities:**
  - *Frost Bolt:* Launches ice missiles at long range on a moderate cooldown with light knockback, smartly prioritizing enemies that are not yet slowed.
  - *Chill Status Effect:* Afflicts struck targets with a chilling slow, reducing their movement speed for a sustained duration.
- **Positioning:** Stays strictly in formation slot.

---

## 5. Enemies & Hazards

### Enemies

#### 1. Lava Slime (Implemented — Hybrid Skirmisher)
- **Role:** Slow, durable area denial skirmisher.
- **Behavior:** Patrols room bounds with idle pauses; hibernates when distant; chases the closest squad member upon detection.
- **Attacks:**
  - *Slime Melee:* Close-range strike on a moderate cooldown.
  - *Lava Spike:* Spits a ranged lava projectile on a moderate cooldown when horizontally aligned with a target in line of sight.
- **Vulnerabilities:** Susceptible to knockback displacement, stun, and frost slow effects.

#### 2. Skeleton (Implemented — Melee Rusher)
- **Role:** Fast close-combat swarm unit and backline diver.
- **Behavior:** Charges aggressively toward the fellowship, weighting its targeting toward healers and ranged backline heroes to exploit gaps in the formation. Can also be raised mid-battle by summoners.
- **Attacks:**
  - *Bone Slash:* Fast close-range melee strike.
  - *Bone Cleave (Heavy Strike):* Occasional heavy melee swing dealing elevated burst damage.

#### 3. Skeleton Archer (Implemented — Ranged Artillery)
- **Role:** Mobile distance harasser.
- **Behavior:** Maintains distance and kites backward away from advancing heroes between shots. Can also be raised mid-battle by summoners.
- **Attacks:**
  - *Bone Arrow:* Fires arrows across long range in any direction with clear line of sight.

#### 4. Necromancer (Implemented — Summoner)
- **Role:** High-priority backline spawner.
- **Behavior:** Kites away from approaching heroes while periodically channeling dark magic to summon undead reinforcements around itself.
- **Attacks:**
  - *Raise Undead:* Places summoning circles nearby that raise `Skeleton` and `Skeleton Archer` minions directly into the room encounter until the summoner is eliminated.

#### 5. Tier 2 Bruiser / Pack Threat (Planned)
- **Role:** Heavy frontline disruptor or fast pack hunter.
- **Behavior:** High-durability bruiser with knockback resistance or fast pack rusher that pressures outer melee rings.

### Environmental Hazards

#### Localized Spike Trap Areas (Planned)
- **Behavior:** Floor spike patches placed in select rooms and corridor sections.
- **Threat:** Dealing damage to any party member walking over them.
- **Gameplay Impact:** Demands cautious steering from the player, as trailing followers swinging around corners can drag across spikes if the leader turns too tightly.

---

## 6. Core Game Loop
1. **Choose Leader & Explore:** Select a starting hero leader and guide the fellowship through procedurally generated corridors and themed rooms.
2. **Draft & Upgrade the Squad:** Touch stranded mystery survivors to draft new heroes into your formation, and collect experience from fallen foes to level up your active hero classes.
3. **Engage Diverse Foes:** Auto-battle fast melee rushers, close the gap on kiting archers, and push deep into crypts to eliminate summoners before their undead waves overwhelm the party.
4. **Mind Hazard Zones:** Steer carefully around localized floor spike traps so trailing squad members stay out of harm's way.
5. **Collect Color-Coded Keys:** Search rooms to locate keys (e.g. Red, Blue, Yellow) needed for locked doors.
6. **Unlock Doors & Advance:** Bring the matching key to locked color-coded doors to open access to deeper dungeon sectors.

---

## 7. Win & Lose Conditions
- **Advancement Goal:** Locate color-coded keys, open matching doors, clear deeper dungeon sectors, and defeat the final boss.
- **Lose Condition:** The run ends immediately if the player's lead character loses all health. Fallen companions are permanently lost for the run, though new survivors can be recruited in unexplored rooms.
