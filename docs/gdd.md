# GAME DESIGN DOCUMENT: ESCAPETEERS

**Working Title:** Escapeteers  
**Genre:** Top-Down Squad Bullet Heaven / Horde Survival  
**Target Platform:** PC  
**Inspiration:** Cannon Fodder (Squad movement & attrition), Gauntlet (Monster nests & dungeon crawls), Vampire Survivors (Zero-button auto-fire & minion swarms), The Lord of the Rings (Fellowship escort dynamic)  

---

## 1. High Concept
Lead a frantic, auto-firing fellowship of survivors through an endless, dynamically generated dungeon. Act as the focal point of your party, steering your surrounding companions past deadly dungeon hazards, smashing relentless monster threats, and rallying recruits discovered across dungeon rooms to replace fallen allies and expand your squad's firepower.

---

## 2. Core Design Pillars
- **The Fellowship Formation:** Your squad surrounds you in layered rings rather than a single-file tail. When you stand still, companions form a protective circle around you; when you walk, allies ahead part out of your way and the group flows around your flanks and rear in a trailing crescent.
- **Stick-Only Spatial Control:** No stance or formation buttons. All shooting, melee strikes, and healing happen automatically. Gameplay revolves entirely around where you stand and when you move: stepping close enough for melee units to reach targets, and moving early enough to pull your delayed party out of danger.
- **Attrition, Healers & Recruitment:** Because followers react slightly after you move, stragglers on the trailing edge can clip hazards, enemy projectiles, or ambushes. Healers mend injured allies between fights, and rescued companions replace allies who fall.
- **Gauntlet Swarm Density:** Enemies patrol dungeon rooms, swarm intruders, and project ranged hazards that deny space.

---

## 3. World & Map Generation
The game world is an endless, chunk-based procedural dungeon:

- **Corridors & Chokepoints:** Narrow passages that restrict how wide the fellowship can spread, forcing the party to bunch together to push through waves before expanding again in open rooms.
- **Open Chambers & Arenas:** Larger rooms housing enemy packs, torch light fixtures, breakable terrain, and waiting companions ready to join the squad.
- **Infinite Dynamic Streaming:** Dungeon rooms generate ahead of the party and despawn far behind them, creating a continuous, seamless run with no loading screens.

---

## 4. The Squad (The Escapeteers)
The squad consists of distinct hero archetypes surrounding the player's lead character. The run begins with the player accompanied by a starter vanguard, and additional survivors wait throughout dungeon rooms, joining the fellowship immediately upon contact.

### Formation & Engagement Behaviors
- **Circle-to-Crescent Movement:** Companions keep personal space from one another and the leader. Moving parts the front of the crowd so the player is always visible, while the party trails behind in an organic crescent.
- **Melee Leashing:** Melee fighters monitor a short leash radius around their formation slot. When a target enters range, they step out of formation to engage and strike, returning to formation once the enemy falls or the leader pulls away.
- **Fixed Formation Discipline:** Ranged casters, archers, and healers remain anchored to their escort positions, never leaving formation to chase enemies.
- **Risk/Reward Positioning:** Hugging enemies pulls the entire squad into melee contact—maximizing damage at the cost of tighter dodge windows and hazard exposure.
- **Follower Navigation & Collisions:** Companions steer along navmesh paths around dungeon walls and obstacles, maintaining line-of-sight checks for ranged projectiles and healing spells.

### Hero Archetypes & Abilities

#### 1. Archer (Ranged Physical)
- **Role:** Long-range single-target sniper.
- **Abilities:**
  - *Snipe Arrow:* Fires swift arrows at distant targets across long range on a moderate cooldown.
  - *Impact Force:* Inflicts heavy knockback on hit, repelling advancing threats away from the formation.
- **Positioning:** Stays strictly in formation slot; requires clear line of sight.

#### 2. Armored Axeman (Melee Brawler)
- **Role:** Sturdy frontline bruiser and crowd disruptor.
- **Abilities:**
  - *Axe Chop:* Rapid melee slashes on a short cooldown with moderate knockback.
  - *Crushing Cleave (Heavy Strike):* Has a chance after successive swings to unleash a devastating heavy chop on a long cooldown, delivering massive burst damage and massive knockback that tosses enemies backward.
- **Positioning:** Steps out on a melee leash to intercept nearby enemies.

#### 3. Knight (Melee Vanguard)
- **Role:** Frontline line-holder and target pin.
- **Abilities:**
  - *Sword Strike:* Fast melee slashes on a short cooldown with zero regular knockback, allowing the Knight to pin enemies in place for squad focus fire.
  - *Shield Slam (Heavy Strike):* Has a chance after successive swings to deliver a heavy strike on a long cooldown, dealing heavy burst damage and sending foes flying with strong knockback.
- **Positioning:** Steps out on a melee leash to lock down advancing targets.

#### 4. Knight Templar (Melee Shock Infantry)
- **Role:** Aggressive frontline defender with high-impact displacement.
- **Abilities:**
  - *Heavy Blade:* Powerful melee slashes on a short cooldown with elevated standard knockback, consistently pushing swarms away from the fellowship.
  - *Smite (Heavy Strike):* Has a chance after successive swings to unleash an empowered strike on a long cooldown, dealing heavy damage with massive knockback.
- **Positioning:** Steps out on a melee leash to create breathing room for ranged companions.

#### 5. Priest (Support Healer)
- **Role:** Dedicated squad sustain and triage.
- **Abilities:**
  - *Divine Heal:* Automatically identifies the most wounded ally within long range and channels healing magic on a moderate cooldown, restoring a large chunk of lost health.
  - *Protective Focus:* Pure support hero; abstains from direct offensive attacks to dedicate attention entirely to party preservation.
- **Positioning:** Stays strictly anchored inside the protective core of the formation.

#### 6. Soldier (Hybrid Melee / Ranged)
- **Role:** Versatile combatant adapting to combat distance.
- **Abilities:**
  - *Ranged Salvo:* While enemies remain at a distance, stays in formation and fires arrows on a short cooldown.
  - *Melee Engagement:* When enemies enter close proximity, draws a sword and steps out on a melee leash, executing fast slashes on a short cooldown and occasional heavy strikes on a long cooldown with massive knockback.
- **Positioning:** Dynamically transitions between formation archery and leash-based melee brawling.

#### 7. Swordsman (Melee Skirmisher)
- **Role:** Rapid-strike duelist specializing in multi-hit damage.
- **Abilities:**
  - *Quick Slash:* Fast sword slices on a short cooldown with zero knockback, maintaining constant pressure on target health.
  - *Flurry Combo (Heavy Strike):* Has a chance after successive strikes to trigger a multi-hit flurry on a long cooldown, striking the target three times in rapid succession for heavy compound damage without scattering the target.
- **Positioning:** Steps out on a melee leash to shred high-priority targets up close.

#### 8. Wizard (Ranged Crowd Control)
- **Role:** Area-of-influence spellcaster and crowd decelerator.
- **Abilities:**
  - *Ice Bolt:* Casts glacial ice missiles at long range on a moderate-to-long cooldown.
  - *Chill Status Effect:* Enemies struck by ice magic are afflicted with a chilling slow effect, drastically lowering their movement speed for a sustained duration and giving the fellowship time to reposition.
- **Positioning:** Stays strictly in formation slot.

### Hero Recruitment & Rarity
- **Recruitment Mechanic:** Unrecruited companions wait in discovered dungeon rooms. Walking any squad member into contact instantly recruits them into the fellowship.
- **Starter Fellowship:** The player begins each expedition supported by a starter vanguard (Priest and Armored Axeman).
- **Encounter Weighting:** Frontline defenders (Armored Axeman, Knight) appear most frequently; specialized fighters (Knight Templar, Swordsman) are uncommon; distinct tactical anchors (Wizard, Archer, Soldier, Priest) are rare discoveries.

---

## 5. Enemies & Hazards

Survival is dictated by spatial awareness, threat prioritization, and dodge timing.

### Current Enemies

#### Lava Slime
- **Classification:** Hybrid Skirmisher / Slime Mob.
- **Behavior:**
  - *Patrol & Hibernation:* Wanders walkable bounds within its home room, pausing intermittently. Hibernates off-screen to save performance until approached.
  - *Chase:* Pursues the closest squad member upon establishing direct line of sight within its detection radius.
- **Combat Abilities:**
  - *Slime Strike:* Executes a close-range melee lunge on a moderate cooldown.
  - *Lava Spike:* Spits a high-velocity lava projectile across long distances on a moderate cooldown whenever aligned horizontally with a squad member with clear line of sight.
- **Vulnerabilities & Reactions:**
  - *Knockback Susceptibility:* Melee and heavy attacks shove the slime backward, decaying over distance.
  - *Frost Vulnerability:* Susceptible to chilling magic (e.g. Wizard ice bolts), visually turning cold blue and crawling at heavily reduced speed.

### Planned Enemies & Dungeon Threats
- **Monster Nests:** Stationary organic or cursed structures (bone piles, spider nests, demon portals) that continuously spawn mob waves until focused down and shattered by squad fire.
- **Swarm Mobs:** Fast, low-HP melee runners that rush the party from multiple angles to overwhelm frontline melee screens.
- **Elite Wardens & Bosses:** High-durability enemies deploying telegraphed ground hazards (lava pools, cleaves, shockwaves), testing the player's ability to steer trailing companions clear of area denial effects.

---

## 6. Core Game Loop
1. **Steer the Fellowship:** Move with the stick or keys to guide your surrounding party through the procedural dungeon.
2. **Position for Maximum Damage:** Close distance to allow melee brawlers on leashes to engage while ranged companions fire from within formation.
3. **Dodge Area Hazards & Projectiles:** Evade enemy ranged spikes and telegraphed strikes early so trailing companions clear hazards in time.
4. **Sustain & Rebuild:** Protect healers to recover from chip damage and seek out stranded heroes in dungeon rooms to replace fallen comrades.
5. **Survive & Score:** Clear rooms, defeat swarms, and push deeper through infinite dungeon corridors until the leader falls.

---

## 7. Lose Condition
- Individual followers can perish and be replaced by finding recruits throughout the dungeon, but the run ends immediately if the player's lead character loses all health.
