# GAME DESIGN DOCUMENT: ESCAPETEERS

**Working Title:** Escapeteers  
**Genre:** Top-Down Squad Dungeon Crawler / Horde Survival  
**Target Platform:** PC  
**Inspiration:** Cannon Fodder (Squad movement & attrition), Gauntlet (Dungeon rooms & key-door progression), Vampire Survivors (Zero-button auto-combat)  

---

## 1. High Concept
Lead an auto-battling fellowship of survivors through a room-based dungeon. Steer your growing party through corridors and chambers, recruit new heroes with distinct skills to expand your squad's firepower, navigate past localized spike hazards, eliminate diverse enemy threats including persistent summoners, and hunt down color-coded keys in distant rooms to unlock matching doors and advance.

---

## 2. Core Design Pillars
- **The Fellowship Formation:** Your squad surrounds you in layered rings. Standing still forms a protective circle around you; walking parts the allies ahead and causes the group to flow around your flanks and rear in a trailing crescent.
- **Stick-Only Spatial Control:** No manual combat or stance buttons. All shooting, melee strikes, and healing trigger automatically based on proximity and cooldowns. Gameplay focuses on spatial navigation: closing distance for melee units, keeping ranged units in line of sight, and steering trailing companions away from hazards.
- **Squad Growth & Attrition:** Rescue unrecruited heroes discovered waiting in dungeon rooms to grow party size and firepower. Healers sustain damaged allies between skirmishes, and new recruits replace fallen companions.
- **Color-Coded Key & Door Progression:** Advancement requires exploring rooms to find color-coded keys that unlock matching doors blocking corridors to new dungeon sections.
- **Mindful Hazard Navigation:** Localized spike trap patches punish careless steering, requiring the leader to take wide turns so trailing followers do not drag across hazard zones.

---

## 3. World & Level Design
The dungeon is procedurally generated as an ascending labyrinth of interconnected rooms and corridors structured around directional progression, exploration, and lock-and-key advancement:

- **Ascending Northward Progression:** The party begins at the southern base of the dungeon in a compact starting chamber scaled to an initial small squad. Pushing northward ascends deeper into the labyrinth where both enemy threat and chamber scale grow to accommodate larger horde battles, while lateral east and west branches offer side routes for recruitment and exploration.
- **Rooms & Corridors:** Corridors funnel the party into tight formations, while chambers provide space for tactical repositioning, companion recruitment, and skirmishes.
- **Atmospheric Dungeon Lighting:** Wall-mounted torches along corridors and free-standing candle posts distributed across room interiors carve warm pools of visibility out of the surrounding darkness, balancing moody shadow contrast with clear combat readability.
- **Color-Coded Doors & Keys:** Locked doors (e.g. Red, Blue, Yellow) block passage to subsequent dungeon sectors. Matching keys are hidden in different rooms, requiring purposeful exploration and route planning.
- **Localized Spike Trap Areas:** Floor spikes placed in select areas (corridor chokepoints, room corners, or guarding key locations). Passing over active spikes deals damage to any squad member who steps on them. Spikes are placed sparingly rather than everywhere.

---

## 4. The Squad (The Escapeteers)
The player guides the lead character as the focal point of the fellowship. Companions are discovered as gray mystery survivors waiting in dungeon rooms and reveal a random hero to join the party upon physical contact. The starting chamber presents unrecruited gray units ahead of the player to initiate the squad's growth.

### Formation & Engagement Behaviors
- **Multi-Ring Inner Support & Auto-Rotate Frontline:** Companions distribute across concentric formation rings based on role and squad size. Fragile healers and ranged heroes prioritize the innermost rings closest to the leader and anchor in the rear arc. Melee brawlers take outer rings and the forward arc, forming an outward-facing perimeter shield that rotates with the leader's facing and movement direction. During movement, frontline units maintain their forward screen while backline companions flow into a trailing crescent.
- **Melee Leashing & Arc Strikes:** Melee fighters watch a leash range around their formation slot. When enemies are detected, they step forward to strike all targets within their forward attack arc, returning to formation when targets die or the leader pulls away.
- **Formation Anchors:** Ranged attackers and healers stay strictly locked to their formation positions, never breaking ranks to chase.
- **Navmesh Steering:** Companions steer along navmesh paths around walls and obstacles, maintaining line of sight to targets.

### Hero Archetypes & Skills

#### 1. Archer (Ranged Physical)
- **Role:** Long-range single-target sniper.
- **Abilities:**
  - *Snipe Arrow:* Fires swift arrows at distant targets across long range on a moderate cooldown.
  - *Impact Force:* Inflicts heavy knockback on hit to push advancing enemies away from the squad.
- **Positioning:** Stays strictly anchored in formation; requires clear line of sight.

#### 2. Armored Axeman (Melee Brawler)
- **Role:** Frontline brawler and crowd disruptor.
- **Abilities:**
  - *Axe Chop:* Rapid melee slashes on a short cooldown with moderate knockback.
  - *Crushing Cleave (Heavy Strike):* Has a chance after successive swings to unleash a heavy chop on a long cooldown, delivering high burst damage and massive knockback.
- **Positioning:** Steps out on a melee leash to intercept nearby threats.

#### 3. Knight (Melee Vanguard)
- **Role:** Frontline anchor and crowd control pin.
- **Abilities:**
  - *Sword Strike:* Fast melee slashes on a short cooldown with zero knockback, pinning enemies in place for squad focus fire.
  - *Shield Slam (Heavy Strike):* Has a chance after successive swings to deliver a heavy blow on a long cooldown, dealing heavy damage and strong knockback.
- **Positioning:** Steps out on a melee leash to lock down advancing targets.

#### 4. Knight Templar (Melee Shock Infantry)
- **Role:** Aggressive frontline defender with high-impact displacement.
- **Abilities:**
  - *Heavy Blade:* Powerful melee slashes on a short cooldown with elevated standard knockback, consistently shoving enemies away.
  - *Smite (Heavy Strike):* Has a chance after successive swings to unleash an empowered strike on a long cooldown with massive knockback.
- **Positioning:** Steps out on a melee leash to create space for backline allies.

#### 5. Priest (Support Healer)
- **Role:** Dedicated squad triage and sustain.
- **Abilities:**
  - *Divine Heal:* Targets the most injured ally within long range and channels healing magic on a moderate cooldown, restoring substantial health.
  - *Protective Focus:* Pure support hero; does not attack, dedicating full attention to sustaining the party.
- **Positioning:** Stays protected within the core of the formation.

#### 6. Soldier (Hybrid Melee / Ranged)
- **Role:** Adaptive combatant adjusting to target distance.
- **Abilities:**
  - *Ranged Salvo:* Fires arrows on a short cooldown while enemies remain at distance.
  - *Melee Engagement:* Draws a blade and steps out on a melee leash when enemies get close, delivering fast slashes on a short cooldown and occasional heavy strikes on a long cooldown.
- **Positioning:** Dynamically transitions between formation archery and leash-based melee combat.

#### 7. Swordsman (Melee Skirmisher)
- **Role:** Rapid-strike duelist specializing in multi-hit damage.
- **Abilities:**
  - *Quick Slash:* Fast sword slices on a short cooldown with zero knockback to maintain pressure.
  - *Flurry Combo (Heavy Strike):* Has a chance after successive strikes to trigger a multi-hit flurry on a long cooldown, striking in rapid succession for heavy compound damage.
- **Positioning:** Steps out on a melee leash to shred high-priority targets.

#### 8. Wizard (Ranged Crowd Control)
- **Role:** Area spellcaster and crowd decelerator.
- **Abilities:**
  - *Ice Bolt:* Launches piercing ice missiles at long range on a moderate-to-long cooldown.
  - *Chill Status Effect:* Afflicts struck targets with a chilling slow, heavily reducing their movement speed for a sustained duration.
- **Positioning:** Stays strictly in formation slot.

---

## 5. Enemies & Hazards

### Enemies

#### 1. Lava Slime (Implemented)
- **Role:** Hybrid skirmisher mob.
- **Behavior:** Patrols room bounds with idle pauses; hibernates off-screen; chases closest squad member upon gaining direct line of sight.
- **Attacks:**
  - *Slime Strike:* Close-range melee attack on a moderate cooldown.
  - *Lava Spike:* Spits a lava projectile across long distances on a moderate cooldown when horizontally aligned with line of sight.
- **Vulnerabilities:** Susceptible to knockback pushback and frost slow effects.

#### 2. Melee Enemies (Planned)
- **Role:** Close-combat rushers.
- **Behavior:** Charge directly toward squad members to breach the fellowship's perimeter and force melee companions to engage.
- **Threat:** Put pressure on frontline defenders and can slip past to reach fragile ranged allies if not blocked.

#### 3. Ranged Enemies (Planned)
- **Role:** Distance artillery.
- **Behavior:** Keep their distance and fire projectiles at squad members from afar.
- **Threat:** Harass backline units and force the player to steer the squad forward into attack range.

#### 4. Summoner Enemies (Planned)
- **Role:** Priority spawner.
- **Behavior:** Hangs back and continuously summons minion waves without stopping until destroyed.
- **Threat:** Overwhelms the squad through sheer numbers if left alive, making them a high-priority target to rush down and eliminate.

### Environmental Hazards

#### Localized Spike Trap Areas
- **Behavior:** Floor spike patches placed in select rooms and corridor sections.
- **Threat:** Dealing damage to any party member walking over them.
- **Gameplay Impact:** Demands cautious steering from the player, as trailing followers swinging around corners can drag across spikes if the leader turns too tightly.

---

## 6. Core Game Loop
1. **Explore the Dungeon:** Guide the fellowship through corridors and open rooms using stick or directional keys.
2. **Grow the Squad:** Locate stranded heroes in dungeon rooms and walk into contact to recruit them, adding new skills and firepower to your party.
3. **Engage Diverse Foes:** Auto-battle melee rushers, return fire against ranged enemies, and focus down persistent summoners before they overwhelm the party.
4. **Mind Hazard Zones:** Steer carefully around localized floor spike traps so trailing squad members stay out of harm's way.
5. **Collect Color-Coded Keys:** Search rooms to locate keys (e.g. Red, Blue, Yellow) needed for locked doors.
6. **Unlock Doors & Advance:** Bring the matching key to locked color-coded doors to open access to new dungeon sectors.

---

## 7. Win & Lose Conditions
- **Advancement Goal:** Locate color-coded keys, open matching doors, and clear dungeon sectors.
- **Lose Condition:** The run ends immediately if the player's lead character loses all health. Fallen companions can be replaced by recruiting new heroes found in dungeon rooms.
