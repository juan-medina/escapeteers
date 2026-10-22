# GAME DESIGN DOCUMENT: ESCAPETEERS

**Working Title:** Escapeteers  
**Genre:** Top-Down Squad Bullet Heaven / Horde Survival  
**Target Platform:** PC  
**Inspiration:** Cannon Fodder (Squad movement & attrition), Gauntlet (Monster nests & dungeon crawls), Vampire Survivors (Zero-button auto-fire & minion swarms), The Lord of the Rings (Fellowship escort dynamic)  

---

## 1. High Concept
Lead a frantic, auto-firing fellowship of survivors through an endless, dynamically generated dungeon. Act as the focal point of your party, steering your surrounding companions past deadly boss traps, smashing relentless monster nests, and rescuing caged recruits to replace fallen allies and grow your squad's firepower.

---

## 2. Core Design Pillars
- **The Fellowship Formation:** Your squad surrounds you in layered rings rather than a single-file tail. When you stand still, companions form a protective circle around you; when you walk, allies ahead part out of your way and the group flows around your flanks and rear in a trailing crescent.
- **Stick-Only Spatial Control:** No stance or formation buttons. All shooting, melee strikes, and healing happen automatically. Gameplay revolves entirely around where you stand and when you move: stepping close enough for melee units to reach targets, and moving early enough to pull your delayed party out of danger.
- **Attrition, Healers & Recruitment:** Because followers react slightly after you move, stragglers on the trailing edge can clip boss AoEs, lava pools, or ambushes. Healers mend injured allies between fights, and rescued captives replace companions who fall.
- **Gauntlet Swarm Density:** Enemies pour continuously from destructible monster nests and guard bosses that deny space with area hazards.

---

## 3. World & Map Generation
The game world is an endless, chunk-based procedural dungeon:

- **Corridors & Chokepoints:** Narrow passages that restrict how wide the fellowship can spread, forcing the party to bunch together to push through waves before expanding again in open rooms.
- **Open Chambers & Boss Arenas:** Larger rooms housing monster nests, caged companions, breakable bone piles, and bosses that cast ground hazards (lava pools, spike traps, shockwaves).
- **Infinite Dynamic Streaming:** Dungeon rooms generate ahead of the party and despawn far behind them, creating a continuous, seamless run with no loading screens.

---

## 4. The Squad (The Escapeteers)
The squad consists of distinct hero archetypes surrounding the player's lead character. All companions are rescued during the run:

- **Circle-to-Crescent Movement:** Companions keep personal space from one another and from the leader. Moving parts the front of the crowd so the player is always visible and unobstructed, while the rest of the party follows with a slight, organic reaction delay.
- **Melee Fighters (Knight, Armored Axeman, Swordsman):** Watch a short **Leash Range** around their formation slot. When an enemy enters it, they step out of formation to close the gap and strike, then return to their slot when the target dies or the leader pulls away.
- **Ranged & Casters (Archer, Wizard):** Never leave their formation slot. They stay protected inside the group and automatically fire arrows or spells at enemies within their **Attack Range**.
- **Hybrid Fighters (Soldier):** Adapt based on distance—staying in their formation slot to shoot their bow at distant targets, and drawing their sword to step out on a melee leash when enemies get close.
- **Support & Hybrid Support (Priest, Knight Templar):** The Priest stays in formation to heal injured allies (and fires light bolts when the party is healthy), while the Knight Templar brawls on a melee leash and pulses restorative wards to nearby companions.
- **Risk/Reward Positioning:** Because ranged units fire from afar while melee and hybrid units hit hardest up close, hugging a boss brings the entire ring into melee reach—maximizing damage at the cost of tighter dodge windows.
- **Future Design Note — Wall Collisions & Navigation:** Followers will be physically blocked by walls and dungeon obstacles rather than passing through them. In tight corridors, doorways, or corner turns, walls will restrict and compress the formation, and companions will need to steer and pathfind around obstacles to rejoin the leader.

---

## 5. Enemies, Nests & Bosses
Survival is dictated by spawn control and hazard positioning:

- **Monster Nests:** Stationary structures (bone piles, spider sacs, demon portals) that periodically spawn mob clusters until destroyed by squad fire.
- **Swarm Mobs:** Fast, low-HP enemies that rush the party from multiple angles, testing your melee screen and ranged coverage.
- **Elite Wardens & Bosses:** High-HP threats that deploy telegraphed ground hazards (lava pools, traps, cleave zones), forcing you to read attacks early and relocate the entire party before trailing followers get caught.

---

## 6. Core Game Loop
1. **Steer the Fellowship:** Move with the stick or keys to guide your surrounding party through the dungeon.
2. **Position for Maximum Damage:** Push close to nests and bosses so melee fighters within your leash range can engage alongside ranged attackers.
3. **Dodge Area Hazards:** Read enemy telegraphs early and move so the trailing edge of your party clears lava pools and traps in time.
4. **Sustain & Rebuild:** Rely on healers to recover from chip damage and break open cages to recruit new companions when squad members die.
5. **Survive & Score:** Clear nests, defeat bosses, and rack up high scores until the leader falls.

---

## 7. Lose Condition
- Individual followers can die and be replaced via cages, but the run ends immediately if the player's lead character loses all health.