# MIREWARD

## D00. Document contract

**Game design and technical architecture · Specification 1.0 · 21 September 2026**

**Tagline:** A borrowed sword. A broken road. A promise worth keeping.

MIREWARD is a single-player, first-person, low-poly medieval action RPG. A penniless hedge knight enters Greyfen Vale looking for paid work and discovers a struggle over who owns its road, its grain, and its future. The player explores a small, continuous valley, fights readable melee encounters, takes contracts, acquires better equipment, and decides what should replace a corrupt toll regime.

This is the design for a **complete, bounded first release**, including its ending and persistent aftermath. The introductory slice is an integration milestone on the way to that release. It is not the final deliverable.

Read alongside [requirements.md](requirements.md) and [tasks.md](tasks.md). Requirements own observable obligations and pass/fail criteria. This document owns the creative canon, default tuning, content IDs, system semantics, and shared interfaces. Tasks own implementation order and handoffs. Resolve contradictions explicitly in all affected documents before implementing; never quietly remove a requirement to pass a task.

Values marked **tuning** can be adjusted after measured playtesting without changing the feature's semantics. All other numbers, enums, content IDs, branch behavior, and transaction rules are contracts. Record tuning changes in the implementation's decision log. This specification is a plan, not a claim that any game code or testing already exists.

### Locked decisions

| Decision | Release 1.0 choice |
|---|---|
| Perspective | First-person only, visible weapon, shield, and simple armored hands |
| Engine | Godot 4 stable, typed GDScript, Compatibility renderer; freeze an exact version in T01 |
| Session | Offline, single-player, pauseable; no account or runtime network dependency |
| Platform | Desktop keyboard and mouse; runnable source on Windows, macOS, and Linux; verified host-platform export |
| World | One authored exterior, three small instanced interiors, fixed authored encounters |
| Scope | Six main quests, six side quests, eight named speaking characters, nine discoverable landmarks |
| Progression | Equipment, money, knowledge, and persistent choices; no XP or skill tree |
| Combat | Light attack, heavy attack, shield block, timed parry, movement; four normal enemy archetypes and one boss |
| Length target | Approximately 60–100 minutes for the main story and 120–180 minutes with exploration; a design hypothesis to playtest |
| Delivery | Fully playable source, original/generated baseline assets, licenses, tests, host build, launch instructions, and verification report |
| Authoring | No Blender, paid asset, API key, or external game plugin required |

### Design pillars

1. **A place worth walking through.** The castle and broken bell tower orient the player; small stories reward detours between them.
2. **A knight with limited means.** Money and equipment matter, but the player cannot bankrupt themselves into a story lock.
3. **Readable, weighty fighting.** Enemies advertise attacks. A shield and a well-timed step matter more than large health bars.
4. **Promises leave marks.** Choices alter people, signs, prices, and the road itself.
5. **Rough surfaces, deliberate composition.** Angular models, small textures, fog, and good lighting support the mood. Visual inconsistency is not an aesthetic goal.

### Explicitly outside this release

Multiplayer; horses; third-person camera; climbing and swimming systems; procedural continents; full stealth simulation; crime, prison, and civilian murder systems; crafting; durability; hunger; romance; voice acting; generative NPC conversations; spellcasting; character creation; skill trees; settlement construction; dynamic faction warfare; an actual day/night calendar; infinite enemy respawning; consoles; mobile; and browser export. Their absence must not leave dead buttons or unfinished menus.

## D01. The world and its argument

### Premise

The winter road into Greyfen was once kept by the monastery of Saint Orra. Its charter required safe passage and grain reserves for bad seasons. A generation ago the abbey burned. Rookwatch's soldiers took over the toll, and a wartime emergency became permanent revenue.

Now Captain Rusk doubles the levy while claiming the crown ordered it. Village carts disappear into his storehouses. Some deserters rob travelers; others feed families the garrison abandoned. The monastery's bell has begun ringing again even though its rope hangs burned through.

The protagonist arrives with a patched coat, a rusted sword, a wooden buckler, and twelve crowns. There is no royal lineage or prophecy. The player's importance grows because they walk the road, hear people out, and survive long enough to carry evidence between them.

The central question is **who should be responsible for keeping a road safe, and what do they have the right to demand in return?** Every faction has a practical answer and someone who pays for it.

### Tone

Melancholy, damp, humane, occasionally dryly funny. Scarcity is visible through repaired roofs, watered stew, and mismatched armor. The supernatural is restrained: stone guardians move in the crypt, distant bells sound, and no character fully explains either. The charter and the captain's fraud are unambiguous; the bell's origin is left uncertain.

Violence is stylized. No dismemberment, gore simulation, torture spectacle, or photorealistic wounds. An enemy falls, its weapon clatters, and the scene grows quiet. Civilians cannot be damaged. Their invulnerability is a scoped interaction rule, not an invitation to a missing crime system.

### Player identity

UI and dialogue call the player **the Hedge Knight**. A fixed obscured identity avoids facial customization and voice choices. First-person gloves and arms match equipped armor. NPCs address actions, never an assumed gender. The opening establishes that the sword was borrowed from someone who expected its return; the last journal line asks whether the player has finally earned something of their own.

## D02. Geography, traversal, and pacing

### World dimensions and coordinates

The exterior is approximately **640 × 640 meters**, with authored terrain and playable routes inside X/Z bounds of −320 to +320. Godot convention: Y is up, north is negative Z, east is positive X, and one unit is one meter. The coordinates below are horizontal layout anchors; terrain fitting can move an anchor by up to 15 meters, documented in the map manifest. Keep the relationship and route times recognizable.

| Landmark ID | Name | Approx. X, Z | Purpose and recognizable silhouette |
|---|---|---:|---|
| lm_brackenford | Brackenford | −110, 140 | Village, inn, forge, contracts; a crooked green roof and waterwheel |
| lm_kings_trace | King's Trace | −30, 30 | Toll checkpoint; two stone posts and a red levy banner |
| lm_briar_camp | Briar Camp | −230, −70 | Wren's neutral deserter camp; striped tarps under leaning pines |
| lm_orra | Saint Orra's Monastery | 180, −95 | Ruined abbey and crypt; split bell tower visible over the forest |
| lm_rookwatch | Rookwatch | 40, −240 | Castle courtyard and undercroft; dark keep against the northern ridge |
| lm_reed_shrine | Reed Shrine | 190, 140 | Ring side quest and free resting point; ribbons on a drowned willow |
| lm_charcoal | Charcoal Kiln | −180, 25 | Smith's hammer and nearby medicine cache; black dome and smoke stain |
| lm_watchtower | Old Watchtower | 170, −220 | Ledger and badge; collapsed upper storey and one lit window |
| lm_ferry | Millpond Ferry | −190, 230 | Lost blankets, Hobb, quiet storytelling; stranded ferry and rope posts |

Start at approximately (32, 252), facing the road toward Brackenford. The robbed cart for MQ01 is near (0, 100), reachable from the village in roughly 30–50 seconds. Approximate safe-route walking times: village to checkpoint 45–70 seconds; checkpoint to monastery 70–100 seconds; village to Briar Camp 70–110 seconds; monastery to watchtower 35–55 seconds; checkpoint to castle 80–120 seconds. These are pacing targets, not speedrun gates.

### Route topology

- The central road links the southern entry, Brackenford, King's Trace, and Rookwatch.
- A western woodland loop joins the village, kiln, and Briar Camp, returning to the road north of the checkpoint.
- An eastern footpath joins the cart, shrine, monastery, and watchtower, reconnecting near Rookwatch.
- Roadblocks create encounters, not invisible requirements to fight. The player can walk around the hostile checkpoint along either loop.
- Rookwatch's public courtyard is explorable early. Its undercroft door remains visibly barred until Ada receives the evidence in MQ05.
- The monastery exterior is open immediately; its crypt can be entered immediately, and its charter puzzle can be solved before MQ03 is assigned.
- Mountain edges, deep reeds, broken bridges, and opaque terrain define the boundary. Fog alone is not a collision wall.

### Interiors

Three separately loaded scenes: `interior_inn`, `interior_crypt`, `interior_undercroft`. Each has stable paired exit IDs and an exterior return transform. The inn is one room plus a sleeping alcove; the crypt has a vestibule, three burial chambers, and charter vault; the undercroft has a storehouse, short guard corridor, and captain's hall. Other buildings use facades, windows, covered porches, and outdoor NPC stations.

Interior exits remain usable during quests. Entering/leaving is a fade, input lock, scene change, navigation synchronization, and safe spawn. A player must never appear inside an enemy, floor, closed door, or transition trigger. Return transforms sit at least 1.5 meters outside the triggering door.

### Opening ten minutes

1. The southern road, creaking sign, ruined monastery silhouette, and one contextual movement hint introduce the setting.
2. A sign directs the player to Brackenford; Mara's nearby contract marker is visible without a full-screen tutorial.
3. Mara offers the cart recovery. Oswin's optional straw dummy explains attack, block, and parry.
4. The cart presents two cutpurses, separated enough to approach one first. The medicine coffer sits in a physical chest.
5. Returning the supplies pays the player, opens the toll investigation, and makes the equipment loop understandable.

Main-story urgency is narrative rather than timed. No quest expires while the player explores. The final decision does not close unfinished side quests.

## D03. Core loop and controls

The loop is **hear a problem → choose a route → read an encounter → fight or bypass it → recover an object or evidence → return or press onward → improve equipment → see a consequence**.

### Default controls

| Action / InputMap ID | Binding | Behavior |
|---|---|---|
| move_forward / move_back / move_left / move_right | W / S / A / D | Camera-relative ground movement |
| look | Mouse motion | Captured mouse, pitch clamped to ±85° |
| sprint | Left Shift | Hold; uses stamina only while actually moving |
| jump | Space | Small traversal jump, grounded only |
| attack_light | Left mouse | One committed light attack; one buffered follow-up allowed |
| attack_heavy | R | One committed heavy attack |
| block | Right mouse | Hold shield; initial guard window can parry |
| interact | E | Focused contextual interaction |
| quick_heal | Q | Use one bandage if available |
| inventory | Tab | Inventory and equipment modal |
| journal | J | Quest log and completed evidence |
| map | M | Stylized discovered-landmark map |
| pause | Escape | Close top modal, otherwise pause menu |

All digital bindings are remappable, including mouse buttons. A binding conflict warns and offers swap or cancel; gameplay bindings cannot steal mandatory Escape/back navigation. Every prompt reflects the actual mapping. Mouse sensitivity and invert-Y are configurable.

**Movement tuning:** walk 4.0 m/s; sprint 6.0 m/s; block 2.2 m/s; acceleration 18 m/s²; jump velocity 4.5 m/s; gravity 16 m/s²; maximum traversable floor angle 45°. Capsule height 1.8 m, radius 0.32 m, eye height 1.65 m. Movement uses `CharacterBody3D`, normalized planar input, floor-aware acceleration, and physics-step integration. Air steering is 30% of ground steering. No crouch, dodge roll, or mantle.

Jump costs 10 stamina; sprint costs 12/s. At zero stamina, sprint falls back to walking. Gravity and player/enemy combat simulation pause in every modal menu. Pointer capture changes only through the central game-mode controller.

### Interaction

An eye-center ray checks a maximum of 2.5 m. A solid wall blocks interaction even if a target trigger extends through it. Only the closest eligible visible target gets a prompt. E performs exactly one interaction on its pressed edge, never each held frame. Interactions cover NPCs, readable notes, containers, doors, rest points, the bell puzzle, and the ending writ table.

## D04. Combat and enemy behavior

### Player attributes and timing

Player maximum health and stamina are both 100. Stamina regenerates at 22/s after 0.8 s without a stamina-consuming action; regeneration is suspended during attack, block, sprint, and healing. There is no passive health regeneration.

Attack phases are `WINDUP → ACTIVE → RECOVERY → IDLE`. A light attack may buffer one following attack during the final 0.12 s of recovery. Blocking and healing cannot cancel an already committed attack. Opening a menu freezes the phase and does not clear costs, damage history, or cooldowns. On resume, held buttons do not create fresh pressed-edge actions.

| Weapon ID | Name | Base damage | Stamina | Windup / active / recovery, seconds | Reach | Base buy price |
|---|---|---:|---:|---|---:|---:|
| rusted_sword | Borrowed Sword | 18 | 16 | 0.25 / 0.12 / 0.43 | 2.0 m | 8 |
| arming_sword | Riveted Arming Sword | 24 | 18 | 0.22 / 0.12 / 0.38 | 2.0 m | 32 |
| falchion | Forester's Falchion | 29 | 22 | 0.30 / 0.14 / 0.46 | 1.9 m | 58 |
| watchblade | Rookwatch Blade | 26 | 17 | 0.21 / 0.12 / 0.32 | 2.1 m | 80 |

A heavy attack uses the equipped weapon's base damage ×1.6 and stamina ×1.8, rounded up for stamina, with fixed 0.60/0.16/0.64 s phases. It deals ×1.5 guard damage against blocking enemies. Damage multipliers are applied before the final health-damage rounding. Insufficient stamina refuses an attack with a brief feedback cue and no animation or partial cost.

### Blocking and parrying

- A shield blocks only incoming attacks within a 120° frontal cone, measured by horizontal defender-forward dot direction-toward-attacker ≥0.5.
- Successful ordinary block costs `ceil(raw_damage × 0.8 × shield_cost_multiplier)` stamina and passes 10% of raw damage to the armor calculation. Against enemy guards, a heavy attack multiplies that stamina cost by a further 1.5 before rounding.
- `wooden_buckler`: multiplier 1.0, price 12. `kite_shield`: multiplier 0.7, price 42.
- A guard started within 0.18 s of impact is a perfect parry if the defender has at least 5 stamina and at least 0.65 s has passed since the last guard start eligible to open a parry window. Parry costs 5 stamina, deals zero health damage, and staggers the attacker for 0.65 s. Holding guard never reopens the window. Player parries only; enemies use ordinary blocks.
- If stamina is below the ordinary block cost, guard breaks: stamina becomes zero, 50% of raw damage reaches armor, and the player cannot attack or block for 0.9 s.
- A rear or side hit outside the cone bypasses shield mitigation.
- Health damage is `max(1, round(raw_damage × shield_pass_through × (1 − armor_reduction)))`, except a perfect parry is exactly zero. `raw_damage` in a DamageRequest is weapon base damage multiplied by the attack multiplier exactly once at attack creation. Both shield and health calculations consume that same value.
- Armor reductions: patched coat 0%; leather jack 12%; mail coat 25%. Armor does not change movement speed in this release.
- After actual health loss, the player has 0.20 s damage invulnerability to prevent simultaneous crowd hits. This window does not apply to enemies and does not restart on a rejected hit.

### Hit detection and feedback

Use a physics shape sweep or sampled swept volume during the active phase, bounded by weapon reach, with a world-geometry line-of-sight check. Never apply damage merely because an enemy is inside a proximity radius. Each `(attacker_id, attack_sequence, victim_id)` can damage at most once. All results resolve on the physics thread. Dead or despawning targets reject subsequent hits.

Light attack hits only the nearest valid victim intersected during that swing; heavy attack also hits only one victim. Walls stop both. Weapon visuals communicate timing but do not own gameplay state. Separate health/guard outcome signals drive sound, small weapon recoil, hit spark, and optional camera shake. There is no required blood effect. Enemy windup poses and audio must remain clear at the default retro resolution.

### Enemy roster

The following are tuning baselines. Normal attacks have 0.14 s active time; listed windup and recovery define the rest of the attack. Gold is awarded once through corpse loot, never both directly and through a container.

| Archetype ID | HP / armor | Damage / reach | Windup / recovery | Walk/chase | Loot crowns | Role |
|---|---|---|---|---|---:|---|
| cutpurse | 45 / 0% | 12 / 1.7 m | 0.45 / 0.85 s | 1.5 / 3.2 m/s | 4 | Nervous slasher; cloth hood, broad windup |
| levy_spearman | 65 / 15% | 16 / 2.5 m | 0.65 / 1.00 s | 1.4 / 2.8 | 6 | Straight thrust; long recovery, red shoulder cloth |
| deserter_raider | 80 / 20% | 20 / 2.0 m | 0.60 / 0.90 s | 1.5 / 3.0 | 8 | Every fourth combat second may guard for 0.8 s; 40 guard stamina, 10/s recovery while not guarding |
| hollow_keeper | 60 / 10% | 14 / 1.9 m | 0.80 / 1.10 s | 1.2 / 2.4 | 0 | Stone burial guardian; no ranged or magical attack |
| captain_rusk | 220 / 20% | See boss rules | See boss rules | 1.3 / 2.8 | 18 | Named final combat encounter |

Enemy state machine: `IDLE/PATROL → ALERT → CHASE → WINDUP → ACTIVE → RECOVER`, with interrupt states `STAGGER`, `RETURN`, and terminal `DEAD`. Detection requires player within 14 m, inside a 120° sight cone, and an unobstructed ray. Within 3 m use a full-circle proximity check that still requires unobstructed geometry. Combat noise alerts hostile allies within 8 m when unobstructed. Damage alerts its recipient even from outside sight range.

Lose sight for 4 s or move beyond a 30 m leash from spawn to trigger RETURN. On return, a living enemy recovers to full health after reaching spawn and remaining out of combat for 5 s. Dead enemies never reset. Enemies pursue the player's navigation position, replan no faster than 5 Hz, and update steering every physics tick. They do not query navigation before the map synchronizes. If stuck for 2 s, replan once; after 6 s, return to spawn only when not visible and not within 10 m of the player. Never teleport a visible attacker.

At most two enemies can hold attack reservations against the player at once; others circle or wait. Reservations expire or release on stagger, death, or disengagement. Each attacker maintains at least 0.25 s separation between the start of its windup and another reservation holder's windup. This is crowd readability, not player invulnerability.

Wren's camp members are neutral and not instances of hostile deserter raiders. Civilian/neutral damage is ignored and does not switch them hostile. Faction reactions are explicit story flags, not a generalized reputation engine.

### Captain Rusk

Rusk confronts the player in the undercroft captain's hall. The player can leave before selecting **Challenge Rusk**. That choice closes the combat gate; Rusk then alternates a thrust (24 damage, 2.5 m, 0.75/0.15/0.85 s) and a sweep (22 damage, 2.2 m, 0.90/0.20/1.10 s). Despite its wide visual arc, the sweep obeys the single-victim rule. Both attacks can be parried.

At ≤110 HP, he speaks one line, changes stance, and reduces recovery durations by 15%; no damage or animation is skipped at the transition. After each two attacks he takes an additional 0.85 s breath. No adds or invulnerable phase. The gate opens on victory or player death/recovery. Leaving the encounter through recovery or loading resets living Rusk to full HP; defeating him persists permanently. The Rookwatch seal is in a fixed chest enabled by his death, so loot physics cannot destroy the story.

### Death, falling, rest, and encounter persistence

Player death transitions once to a death panel, then respawns on confirmation at the last activated rest point with full health/stamina. Lose `min(12, floor(crowns × 0.10))` crowns. Keep equipment, quest objects, quest progress, opened containers, discovered landmarks, and defeated enemies. Pending interaction transactions either completed before death or did not occur; no partial rewards.

Initial rest point is Brackenford's roadside shrine, already unlocked. Reed Shrine, the monastery exterior shelter, and the inn are additional rest points. Rest fills health/stamina, sets respawn anchor, and saves. Outdoor resting is free. The inn costs 4 crowns unless SQ02 is complete. Rest is refused while a hostile is actively engaged or within 15 m with line of sight. It resets living encounters to spawn/full HP; defeated enemies remain defeated.

There is no swimming. An out-of-bounds fall or deep-water trigger returns the player to the current scene's last safe anchor, removes 10 health but cannot reduce health below 1, and resets a live boss encounter if necessary. This does not charge the death coin penalty or award enemy deaths. A safe-anchor candidate must be grounded, navigable, outside hazards/door triggers, and free of overlap. Emergency fallback is the village shrine.

## D05. Inventory, money, and progression

### Item definitions

Every item has a stable ID, display name, category, icon, description, base price, maximum stack, and optional equipment/consumable fields. Definitions are immutable resources; quantities and ownership live in session state.

| Item ID | Type | Price | Effect / source |
|---|---|---:|---|
| rusted_sword | Weapon | 8 | Starting Borrowed Sword; combat table above |
| arming_sword | Weapon | 32 | Smith stock; also SQ01 reward |
| falchion | Weapon | 58 | Smith stock |
| watchblade | Weapon | 80 | MQ05 reward; not stocked by shop |
| wooden_buckler | Shield | 12 | Starting shield; multiplier 1.0 |
| kite_shield | Shield | 42 | Smith stock; also SQ05 reward; multiplier 0.7 |
| patched_coat | Armor | 6 | Starting armor; 0% reduction |
| leather_jack | Armor | 40 | Smith stock; 12% reduction |
| mail_coat | Armor | 85 | Smith stock; 25% reduction |
| bandage | Consumable | 8 | +35 HP after 0.8 s uninterrupted use |
| bread | Consumable | 5 | +15 HP after 0.3 s uninterrupted use |
| tonic | Consumable | 14 | +50 stamina after 0.5 s uninterrupted use |
| cart_medicine | Quest | — | MQ01 fixed cart coffer |
| toll_receipt | Evidence | — | MQ02 checkpoint notice/receipt box |
| orra_charter | Evidence | — | MQ03 vault |
| grain_ledger | Evidence | — | MQ04 watchtower chest |
| rookwatch_seal | Evidence | — | MQ05 captain's chest |
| smith_hammer | Quest | — | SQ01 kiln crate |
| ferry_blankets | Quest | — | SQ02 ferry barrel |
| hobb_ring | Quest | — | SQ03 shrine offering bowl |
| votive_candle | Quest | — | SQ04 three authored pickups; count capped at 3 |
| ada_badge | Quest | — | SQ05 watchtower locker |
| camp_medicine | Quest | — | SQ06 raider cache near kiln; distinct from cart medicine |

There are **23 item definitions**, including 12 normal equipment/consumable definitions and 11 quest/evidence definitions. Crowns are an integer currency field, not an inventory item.

Start with 12 crowns, Borrowed Sword, Wooden Buckler, Patched Coat, two bandages, and one bread. All starting equipment is equipped.

Consumables cannot start while their affected resource is full, during an attack, or while another consumable is in use. Damage/death cancels consumption without charging the item; successful completion charges once and caps the resource at its maximum. On a physics tick containing both damage and consumption completion, resolve damage/cancellation first. Equipment cannot change during committed combat/healing actions or scene transitions.

### Capacity and transactions

Sixteen normal stack slots, equipment stack limit 1, consumables stack limit 10. Equipped items still occupy a normal slot and cannot be sold until unequipped; the last owned melee weapon cannot be sold. Quest/evidence objects use a separate unlimited key-item collection and cannot be sold or discarded. Handing in a quest object removes it from carried key items but leaves its permanent acquisition/evidence flag intact.

Picking up ordinary loot previews capacity; if insufficient, unclaimed items stay in that persistent container. Quest rewards always pay currency and story changes immediately and atomically. Equipment/consumables that will not fit enter a persistent `pending_delivery` queue, shown in inventory as **Unclaimed rewards**; claiming is capacity-checked and cannot duplicate. Notifications must distinguish received and pending items.

Buying atomically validates item, stock, quantity, capacity, and crowns before mutation. Selling atomically validates ownership, equipped status, quest status, and minimum-weapon rule. Any failure changes nothing. Buy price is `ceil(base_price × ending_shop_multiplier)`; sell price is `floor(base_price × 0.35)` and never depends on ending. Prices cannot become negative and buying/selling cannot create an arbitrage profit.

Oswin stocks one each of arming sword, falchion, wooden buckler, kite shield, leather jack, and mail coat. Sold equipment is removed from ownership and is not added back to shop stock in this release. Tamsin has unlimited bread, bandages, and tonic, constrained by the player's finite crowns. No random loot tables: each container and enemy carries authored deterministic contents. No XP, repair, crafting, or random-stat gear.

### Economy intentions

MQ01 pays enough to make healing or progress toward a weapon an intelligible choice. SQ01 provides a reliable weapon improvement without saving money. Mail is a meaningful late purchase. Free outdoor rest and bypass routes keep all main quests possible at zero crowns. No main objective consumes purchasable equipment or requires a toll payment.

## D06. Cast, dialogue, and small stories

### Eight named speakers

| NPC ID | Character / fixed station | Role, voice, and signature detail |
|---|---|---|
| mara_venn | Reeve Mara Venn / village well | Practical, exhausted, refuses grand speeches; counts sacks on her fingers |
| oswin_pike | Oswin Pike / village forge | Smith; dry humor, quietly repairs things for free |
| tamsin_reed | Tamsin Reed / inn interior | Innkeeper; keeps a guest ledger full of unpaid names |
| sister_elian | Sister Elian / monastery exterior shelter | Former abbey keeper; careful about the difference between faith and records |
| hobb_fenwick | Hobb Fenwick / ferry landing | Ferryman with no working ferry; stubborn tenderness beneath complaints |
| ada_vey | Ser Ada Vey / Rookwatch courtyard gate | Warden who knows an order and an excuse are different things |
| wren_kest | Wren Kest / Briar Camp | Deserter leader; feeds dependents, admits her people have harmed others |
| captain_rusk | Captain Rusk / undercroft hall | Competent administrator of a cruel arrangement; polished boots in a flooded cellar |

NPCs use idle animation and small station movement only. They do not need simulated daily schedules. Quest markers and dialogue options react to flags; they never relocate as a hidden prerequisite. Rusk is the only named speaker who becomes a damageable enemy.

### Dialogue presentation and authoring rules

Text panel with speaker name, at most three visible choices before scrolling, keyboard/mouse selection, and an explicit Leave option except during the short committed ending confirmation. No voice acting. Opening dialogue pauses simulation; closing restores the previous gameplay state. A character's greeting is selected by priority: relevant turn-in, active objective, newly available main quest, side quest, ending aftermath, ordinary greeting. Shop and rest options remain accessible when other dialogue is available.

Dialogue is data, not hardcoded UI behavior. Conditions are a whitelist of known predicates; effects call validated domain transactions. A line may have at most 45 words. Main exposition can be split over several nodes. Choice text must reveal material costs and irreversible outcomes before confirmation.

The lines below are canonical minimum copy. Agents may add concise connective lines in the same voice, but must preserve the given information, branch meanings, and character motivations.

| Speaker | Greeting / interaction lines | Aftermath line |
|---|---|---|
| Mara | “If you're looking for a lord, keep walking. If you're looking for work, we have more than we can afford.” / “The cart carried medicine. Take the coins from my desk if you must. Bring back the box.” | Charter: “We voted for a road keeper. Astonishing how many people suddenly had opinions about ditches.” |
| Oswin | “A sword's just a promise with an edge. Yours has seen some difficult negotiations.” / “My hammer went missing at the kiln. Bring it back and I'll give you something worth sharpening.” | “You've made enemies with better armor. Sensible time to visit a smith.” |
| Tamsin | “Four crowns for the bed. The roof's included, even where it leaks.” / “Blankets went to the ferry before the flood. My guests would like them back.” | “People have started paying old tabs. I may have to learn arithmetic.” |
| Elian | “The bell has no rope. That is an observation, not an explanation.” / “Saint Orra promised shelter before judgment. Her successors preferred the reverse.” | “A charter cannot make people kind. It can make cruelty harder to call a duty.” |
| Hobb | “The ferry hasn't moved in three weeks. Best safety record on the river.” / “My wife's ring is at the reed shrine. I left it there angry. I'd like not to leave it there forever.” | “She'd have called all this a fuss. Then she'd have made you supper.” |
| Ada | “An order bears a seal. An excuse usually borrows one.” / “Bring me the abbey's charter and the grain account. I will open a door. What you do beyond it is yours.” | Warden: “If we keep the road, we answer for everyone who walks it.” |
| Wren | “Some of us deserted a war. Some deserted a wage that never came. A few just liked the trees.” / “We took grain. Rusk took grain and called the receipt a law.” | Amnesty: “We'll put our names on it. That makes running harder.” Restitution: “The first cart goes back tomorrow. Empty hands this time.” |
| Rusk | “You see stolen bread. I see a garrison that stayed when the crown stopped paying.” / “Show that paper to the hungry and see whether they can eat it.” | At half health: “Very well. No more ceremony.” |

### Environmental readable copy

1. **Southern sign:** “BRACKENFORD — Work, shelter, lawful measures. ROOKWATCH — Toll payable on demand.” Someone scratched out “lawful.”
2. **Toll notice:** “By emergency authority: grain levy doubled until further notice.” A newer date has been painted over an older one.
3. **Receipt:** “Six sacks received. Two entered. Difference retained for discretionary provision. R.”
4. **Abbey inscription:** “Reed for the traveler. Stone for the shelter. Flame for the watch. Offer them in the order of mercy.”
5. **Charter excerpt:** “The road shall be kept for passage, and the granary for want. Neither office shall become a private purse.”
6. **Ledger:** “Village levy: forty sacks. Garrison issue: eleven. Northern sale: twenty-nine.” Names repeat beneath several missing carts.
7. **Ferry ledger:** “Paid: flour, two hens, one roof repair. Owed: nothing worth mentioning.”
8. **Captain's order:** “No receipts to be issued for reserve transfers. Existing records to be surrendered.”
9. **Broken bell plaque:** “For those who keep a light when no one is expected.”

Readables open an accessible text panel. Crucial evidence text is retained in the journal. Decorative writing must not be the only source of an objective instruction.

## D07. Quest and consequence bible

### Universal quest rules

Each quest has `LOCKED`, `AVAILABLE`, `ACTIVE`, `READY`, `COMPLETED` states. No FAILED state is needed because release quests cannot expire or lose their required NPC. Main quests unlock sequentially, but acquisition/discovery events are permanent and reconcile when a quest activates. Picking up the charter or ledger early must advance the later quest correctly. Readables, enemy deaths, and puzzle completion also persist independently of quest activation.

Objectives have explicit IDs and predicates. A quest state never depends solely on receiving an event at exactly the right moment: after load, activation, or scene change, recompute predicates from world/session state. Turn-in is one idempotent transaction keyed by `quest_id + completion`; branch choice transactions also have stable keys. Main evidence cannot be consumed or discarded by a side quest.

A journal always shows the next action, location hint, progress count where relevant, and whether turn-in is available. One tracked quest supplies a compass/map hint. Indoor objectives point to the correct entrance while outside. Main quests are never silently activated by accidentally interacting with the final choice object.

### Main campaign

| Quest | Unlock / objective sequence | Reward and durable changes |
|---|---|---|
| mq_01_bread_and_iron — Bread and Iron | Available at start. Accept from Mara → acquire `cart_medicine` from cart coffer → return to Mara. Fighting the two nearby cutpurses is optional if the coffer can be reached safely. | 18 crowns + 1 bandage. Remove carried cart medicine, retain its acquisition flag. Unlock MQ02. |
| mq_02_the_kings_due — The King's Due | After MQ01. Mara asks for proof → read toll notice and acquire `toll_receipt` at checkpoint box → return to Mara. Both actions are accessible without paying money. | 22 crowns. Receipt becomes journal evidence and stays a key item. Unlock MQ03. |
| mq_03_a_bell_without_rope — A Bell Without a Rope | After MQ02. Speak to Elian → solve crypt puzzle → acquire `orra_charter` → show Elian. Early puzzle/charter actions count. | 28 crowns. Elian attests the charter; unlock MQ04. |
| mq_04_names_in_the_ledger — Names in the Ledger | After MQ03. Speak to Wren → acquire `grain_ledger` from watchtower chest → speak to Wren and choose amnesty or restitution → report to Mara. | 30 crowns. Set `wren_terms` to `amnesty` or `restitution`, keep ledger evidence, unlock MQ05. Neither choice changes combat access or gold. |
| mq_05_a_debt_in_stone — A Debt in Stone | After MQ04. Present charter + ledger to Ada → undercroft unlocked → challenge and defeat Rusk → acquire `rookwatch_seal` from his chest → report to Ada. | 40 crowns + Watchblade, with overflow delivery if needed. Unlock MQ06. Rusk remains dead. |
| mq_06_the_last_toll — The Last Toll | After MQ05. Speak to Mara → use village writ table → review three resolutions and their costs/benefits → confirm exactly one. | Set ending, world aftermath, and completed campaign atomically. Save before presenting epilogue. No currency or item reward. |

### Main quest dialogue choices

- **MQ01:** Mara: “The cart stopped on the south road. Medicine in a blue box. If the men around it are hungry, that doesn't make the box theirs.” Choices: “I'll bring it back.” / “Tell me about the road.” / “Not yet.” Turn-in: “That's three fevers we can stop arguing with. Eighteen crowns, as promised.”
- **MQ02:** Mara: “Find a receipt. I can argue with a soldier. I need something I can put in front of a judge.” Turn-in: “Six taken, two declared. Even I can afford that arithmetic.”
- **MQ03:** Elian: “The charter survived below the chapel. The keepers still guard their order: reed, stone, flame. It was meant to teach mercy.” On return: “The words are plain. Keeping them will be harder.”
- **MQ04:** Wren: “The account is in the old tower. Bring it here, and I'll put names to the numbers.” After recovery: “I want my people alive when this is over.” Choices: **“Testify, and I will argue for amnesty.”** / **“Testify, and repay what you took.”** Both grant testimony. Mara's report: “We will remember both the names and the promise.”
- **MQ05:** Ada: “This is enough. The storehouse door is open. Rusk has kept the seal below.” Rusk offers **“Challenge Rusk.”** / **“Leave.”** After victory Ada says: “A captain is gone. A road still needs keeping. Take the seal to Mara.”
- **MQ06:** Mara: “We have the charter, the account, and the seal. There won't be a cleaner moment. Tell us what you are prepared to stand behind.” Present the three choices below with a confirmation panel; backing out changes nothing.

### Bell puzzle

Three waist-height stone chimes carry reed, stone, and flame symbols plus text labels. Required order: **reed → stone → flame**. Each correct activation lights one marker. An incorrect activation resets progress to zero with a low bell tone; it never damages the player or destroys the puzzle. On the third correct activation the vault door opens permanently. An adjacent readable states the clue; Elian can repeat it. Save partial progress as zero unless solved, preventing an ambiguous half-state after loading. Solved state and charter collection are separate flags.

### Six side quests

All side quests remain available after the ending and may be completed in any order after meeting their giver. SQ05 and SQ06 do not require the corresponding main-story meeting. Early pickups reconcile when accepted.

| Quest ID / title | Giver and exact completion condition | Reward / consequence |
|---|---|---|
| sq_01_a_smiths_hand — A Smith's Hand | Oswin; obtain `smith_hammer` from kiln crate, return it | 12 crowns + Arming Sword; hammer removed |
| sq_02_a_warm_room — A Warm Room | Tamsin; obtain `ferry_blankets` from ferry barrel, return them | 10 crowns; inn rest becomes permanently free; blankets removed |
| sq_03_what_the_reeds_keep — What the Reeds Keep | Hobb; obtain `hobb_ring` from shrine offering bowl, return it | 18 crowns + 1 bandage; ring removed |
| sq_04_three_small_lights — Three Small Lights | Elian; collect three distinct `votive_candle` pickups around monastery graves, return them | 15 crowns + 2 bandages; candle count consumed; three lights appear at shelter |
| sq_05_the_broken_badge — The Broken Badge | Ada; obtain `ada_badge` from watchtower locker, return it | 20 crowns + Kite Shield; badge removed; Ada wears restored badge |
| sq_06_no_clean_hands — No Clean Hands | Wren; obtain `camp_medicine` from raider cache near kiln; choose to deliver to Wren or Mara | 10 crowns either way; remove medicine; set `medicine_recipient` to `camp` or `village`; unique recipient dialogue and epilogue sentence |

Side-quest turn-in copy: Oswin, “There. A blade that won't apologize on the first swing.” Tamsin, “A warm bed when you need one. Call it an investment in repeat business.” Hobb, “Thank you. That's all I've got that fits.” Elian, “Three lights. A small answer to a large dark.” Ada, “I thought I had lost the right to wear it.” Wren, “There are children under those tarps. They don't get a vote in what we call ourselves.” Mara receiving camp medicine, “I'll tell them where it came from. They can decide what to forgive.”

The medicine choice is shown before committing, including “This decides who receives the medicine.” The other recipient remains available for all unrelated quests. No reward is granted twice if the player speaks to both.

### Ending resolution and playable aftermath

| Ending ID / choice | Visible systemic consequences | Epilogue core text |
|---|---|---|
| charter — Restore the village charter | Village banner becomes reed-green. Road checkpoint hostiles become neutral road keepers; defeated checkpoint guards stay dead. Shop buy multiplier 0.85. Mara displays a public grain tally. | “The road belonged to no single hand. Its keepers were named in the square, its grain counted in daylight. Greyfen became no paradise. It became a place where an answer could be demanded.” |
| warden — Bind the wardens to an oath | Ada's silver banner replaces Rusk's red. Surviving checkpoint hostiles become neutral wardens; defeated ones stay dead. Shop buy multiplier 0.95. Gate notice states a fixed public levy. | “The toll remained, but the ledger opened. Ada put her name beneath every order. Some called it a better cage. Others called it a road they could finally travel.” |
| free_road — Break the toll authority | Checkpoint soldiers withdraw and their extant actor spawns are disabled. Toll bar and red banner are removed. Shop buy multiplier 1.00. A repaired traveler sign replaces the notice. | “No seal claimed the road. Carts passed beneath an empty arch, and every village learned how much work freedom could be. For a season, at least, no one paid to go home.” |

Epilogue contains three panels: chosen ending text; Wren terms and medicine result; the player's departure/continuation. Wren amnesty sentence: “The deserters signed their names and took work where they could find it.” Restitution sentence: “Wren's first repayment arrived on a cart that carried no armed escort.” If SQ06 incomplete: “The sick in the valley still waited on small mercies.” Camp medicine: “Under the tarps, the fevers broke.” Village medicine: “At the village well, another list of names grew shorter.” Final panel: “You came with a borrowed sword. What you owed the valley was now a thing you had chosen.”

Buttons: **Return to the valley**, **Main menu**. The completed quest journal can replay the epilogue using current side-quest flags; the chosen ending never changes. Replaying must not apply consequences or rewards again. All side quests, shops, free travel, and unopened containers remain functional afterward.

## D08. Art, rendering, animation, and audio

### Art direction

Human proportions, simple readable forms, slightly oversized weapons and helmets, worn planar surfaces. Houses lean slightly but doors are traversable. Stone uses gray-green blocks; roofs are faded moss and russet; polished metal is rare. Approximate palette: peat `#242B28`, fog `#A8B2AA`, stone `#68736B`, reed `#777844`, rust `#824D3C`, warm light `#E1B978`, parchment `#D8CEB1`.

Textures generally use 64–256 pixel dimensions, nearest filtering for deliberate pixel detail, and restrained contrast. Repeated world textures can use mipmaps to reduce distant shimmer; do not blindly disable mipmaps everywhere. UI icons and text stay sharp at native window resolution. Avoid modern glossy plastic materials and random asset-pack scale changes.

### Dependency-free baseline asset production

Required assets must be generated or authored inside the project with local tools. Build reusable low-poly meshes from intentional primitive assemblies or procedural mesh scripts, then save reusable scenes/resources. Do not ship visible debugging capsules or uncolored gray boxes as characters/buildings. A knight needs distinct boots, greaves, torso, upper/lower arms, gauntlets, helmet, shield, and weapon silhouette even when those parts are simple rigid meshes.

Actor animation may use rigid articulated parts and `AnimationPlayer`; skeletal skinning is not mandatory. Required clips/poses: idle, locomotion, windup, attack, block, stagger, death. The captain needs distinguishable phase stance and thrust/sweep poses. First-person weapons need idle, light, heavy, guard, parry recoil, and healing poses. Gameplay timing remains authoritative in combat state, with animations synchronized to it.

Required environmental families: cottage, inn, forge, road gate, wall/keep, monastery arch/tower, crypt room, undercroft room, bridge/ferry, ruined watchtower, tent/kiln, foliage/rocks, and props. Reuse supports consistency. Required props include named quest containers, writ table, three chimes, shrine, banners, signs, and corpse-loot marker. Original small texture/icon atlases and synthesized audio are acceptable finished assets when they meet visual/audio acceptance criteria.

Optional asset packs may improve a later pass but may not be necessary for a working build. If imported, use known licensed sources, record exact source/license, and keep the same visual scale. Prefer glTF/GLB with included materials. No paid asset or login can block a task. Blender can improve meshes later but is not an installation dependency.

### Rendering contract

Use Compatibility rendering throughout. Depth fog supplies distance atmosphere; volumetric fog, screen-space GI, and other Forward+-only effects are not required. One directional sun casts shadows. Torch/lantern light is local, mostly unshadowed, and limited by proximity. Exterior time is fixed late afternoon; crypt and undercroft use authored interiors. There is no simulated time-of-day or weather gameplay.

Default **Retro** mode renders the 3D view at 540 pixels high with width derived from the actual aspect ratio and upscales with nearest filtering. **Native** renders at window resolution. UI lives outside the low-resolution viewport at native resolution. Both modes preserve camera framing, input sensitivity, interaction ray direction, and readable menus. Letterbox extreme aspect ratios outside 4:3–21:9 rather than stretch.

Graphics options: Retro/Native, shadows low/high/off, fullscreen/windowed, VSync, optional camera shake, and view bob amount including zero. FOV is vertical, default 75°, adjustable 60–95°. View bob defaults to a subtle 0.02 m amplitude. No chromatic aberration, compulsory motion blur, or flashing damage overlay.

### Sound and music

Five buses: Master, Ambience, Effects, UI, Music. All levels are adjustable and persisted separately from game saves. Source assets are original or have an included compatible license. A simple original drone/instrumental bed is sufficient; melody must not be copied from an existing game.

Required sound events: footsteps on dirt/stone/wood; swing; metal impact; shield block; parry; guard break; hurt; death; item pickup; chest/door; UI accept/back; bandage; puzzle correct/reset/solved; quest completion; distant bell. Zone ambience distinguishes village hammer/water, forest wind, monastery crows/bell, and undercroft drips. No audio autoplay before the main menu is ready. Gameplay audio respects pause; UI audio remains active. Critical cues have matching visual feedback and never rely on sound alone.

## D09. Interface and accessibility

Title screen: Continue, New Game, Load, Settings, Credits, Quit. Continue is disabled with a clear label if no valid save exists. New Game asks before overwriting the current autosave but never silently overwrites a manual slot. Load shows three manual slots and one autosave with timestamp, chapter, and location.

Continue selects the newest valid slot by saved timestamp. A newer corrupt/incompatible slot is skipped with an explanatory notice; it is not deleted. New Game resets all session-owned state while retaining user settings.

HUD: compact health/stamina bars; equipped item icon; contextual E prompt; unobtrusive compass; tracked quest title and short objective. Enemy health appears only for the targeted/recently hit hostile. Boss bar appears only during Rusk's active fight. Damage cues point toward an attacker without replacing readable animation.

Inventory: normal slots, equipment slots, key items/evidence, currency, pending rewards, item descriptions, buy/sell comparison where relevant. Journal separates active/completed quests and retains important documents. Map is an authored top-down illustration or code-drawn schematic with revealed landmarks and player position; it is not an unexplained developer minimap. Undiscovered landmarks are hidden. Paths and terrain hints may remain visible. No fast travel.

All menus support keyboard and mouse, visible focus, Escape/back behavior, wrapping or scrolling that keeps focused content visible, and text scale 100/125/150%. At 1280×720 with maximum text scale, essential buttons and numbers remain accessible. Color is never the only cue for quest completion, hostility, item category, or puzzle order. Subtitles are unnecessary without voice, but all spoken/narrative content is text.

Pause, inventory, map, journal, dialogue, shop, settings, death, and epilogue are explicit mutually exclusive modes with a modal stack for subordinate panels. No weapon swing on clicking a UI button; no stuck cursor after closing. Losing window focus auto-pauses gameplay and clears pending input edges.

## D10. Technical architecture and module ownership

### Engine/environment policy

T01 chooses an installed compatible stable Godot 4 release, or obtains an official stable release if tools/network permit. Freeze its exact version and matching export-template version in `.godot-version` and the README. Do not switch engine versions halfway through the task sequence. If the environment cannot run Godot, continue creating auditable source but label runtime gates unverified; do not fabricate successful runs. Prefer no addons or runtime dependencies.

Use typed GDScript and named resources. No gameplay service talks directly to a menu node, and no UI script directly edits quest state or money. Physics and scene-tree operations remain on the main thread. Keep domain calculations small and testable independently of visible scenes.

### Repository layout

```text
project.godot
.godot-version
export_presets.cfg
README.md
specs/{design,requirements,tasks}.md
autoload/{game_session,content_db,event_bus,save_service,audio_service}.gd
core/{types,combat_math,transactions,quest_predicates}.gd
data/{items,enemies,quests,dialogue,loot,world,localization}/
scenes/{boot,main_menu,game_root}.tscn
scenes/player/
scenes/actors/
scenes/world/{exterior,inn,crypt,undercroft}/
scenes/ui/
scripts/{player,combat,ai,world,inventory,quests,dialogue,ui}/
assets/{models,materials,textures,icons,audio,fonts}/
tools/{generate_assets,bake_world,validate_content}.gd
tests/{run_all,unit,integration,fixtures}/
docs/{decisions,progress,verification,asset_manifest,traceability}.md
docs/handoffs/Txx.md
builds/                         # ignored generated exports
```

This layout is normative at the directory level; minor filenames within an owned module may change if public interfaces and handoffs stay accurate. `.godot/`, builds, and machine-specific absolute paths are not committed.

### Shared types and state

Use StringName stable identifiers, with JSON serialization as strings. Never persist NodePaths, instance IDs, live object references, or scene-tree indices as identity. IDs are unique across the relevant registry, while persistent entity IDs are globally unique.

| Type | Required fields / meaning |
|---|---|
| ItemDef | id, name_key, description_key, category, icon_path, base_price, max_stack, equipment/consumable data |
| EnemyDef | id, max_health, armor, move speeds, perception, attack definitions, loot definition |
| QuestDef | id, prerequisites, giver_id, objective definitions, rewards, completion effects |
| DialogueDef | id, npc_id, nodes; each node has text_key, choices, conditions, domain effects |
| InteractionOffer | entity_id, prompt_key, allowed, reason_key, action_id |
| ActionResult | ok: bool, code: StringName, message_key: StringName, payload: Dictionary |
| DamageRequest | attacker_id, attack_sequence: int, victim_id, raw_damage: float, attack_kind, origin: Vector3, source_faction |
| DamageResult | outcome: hit/blocked/parried/guard_broken/ignored/killed, health_damage, stamina_damage, stagger_seconds |
| ItemStack | stack_id, item_id, quantity; equipment stacks have quantity 1 |
| SessionState | player snapshot, inventory, key_items, evidence flags, quest records, world records, choices, transaction ledger, pending_delivery |

Content uses `.tres` resources or validated JSON loaded into typed structures. Pick one format per registry in T02 and preserve it. Conditions/effects use explicit enums/whitelisted operations; never evaluate arbitrary strings as code.

Initial choice values are `wren_terms=unset`, `medicine_recipient=unset`, and `ending=none`. MQ01 starts AVAILABLE, MQ02–MQ06 LOCKED, and side quests AVAILABLE at their givers but absent from the active journal until accepted. The initial transaction ledger, pending deliveries, evidence, defeated-entity list, and discovery list are empty. The village shrine is the preactivated respawn anchor even before its landmark is discovered. Puzzle solved, free inn, restored badge, and shelter lights start false. Save validation permits unset choices only when their committing quest step has not completed.

Document concrete objective IDs in T12 using `quest_id/verb_target` names, for example `mq_02_the_kings_due/read_toll_notice`; physical content references those IDs or their predicates rather than ad hoc duplicate counters. Acquisition flags are per item/evidence ID and unique pickup entity, while dialogue steps have distinct conversation flags. Merely meeting Elian early does not automatically count as her later charter attestation.

### Public API contract

The signatures below express GDScript-facing contracts; types declared in T02 must make them real. Unrelated agents may consume but not rename them without an integration change approved by the orchestrator and recorded in `docs/decisions.md`.

| Owner | Public method / responsibility |
|---|---|
| ContentDB | `get_item(id: StringName) -> ItemDef`, equivalent typed getters for enemy/quest/dialogue; reject unknown IDs at validation |
| GameSession | `new_game() -> void`, `snapshot() -> Dictionary`, `restore(snapshot: Dictionary) -> ActionResult`; owns one mutable session |
| GameModeController | `push_mode(mode: StringName) -> ActionResult`, `pop_mode() -> void`; controls pause, cursor, focus, input release |
| InteractionComponent | `get_offer(actor_id: StringName) -> InteractionOffer`, `interact(actor_id: StringName, action_id: StringName) -> ActionResult` |
| CombatComponent | `request_attack(kind: StringName) -> ActionResult`, `set_guard(held: bool) -> void`, `receive_hit(request: DamageRequest) -> DamageResult` |
| InventoryService | `try_add(item_id, quantity, source_id) -> ActionResult`, `try_equip(stack_id) -> ActionResult`, `try_consume(stack_id) -> ActionResult`, `claim_pending(delivery_id) -> ActionResult` |
| EconomyService | `try_buy(shop_id, item_id, quantity, transaction_id) -> ActionResult`, `try_sell(shop_id, stack_id, quantity, transaction_id) -> ActionResult` |
| QuestService | `activate(quest_id) -> ActionResult`, `reconcile() -> void`, `complete(quest_id, transaction_id) -> ActionResult`, `choose(choice_id, value, transaction_id) -> ActionResult` |
| DialogueService | `start(npc_id) -> ActionResult`, `choose(node_id, choice_id) -> ActionResult`, `close() -> void`; validates choice conditions at commit time |
| WorldStateService | `get_entity_state(entity_id) -> Dictionary`, `apply_transaction(changes, transaction_id) -> ActionResult`; centralizes persisted entity mutations |
| WorldRouter | `travel(scene_id, entrance_id) -> ActionResult`, `recover_player(reason) -> ActionResult`; applies world state after scene instantiation |
| SaveService | `save_slot(slot_id) -> ActionResult`, `load_slot(slot_id) -> ActionResult`, `list_slots() -> Array`; validated snapshot boundary |
| AudioService | `play_event(event_id, world_position_or_null) -> void`, bus settings; presentation only |

Services beyond the five named autoloads are owned children of `GameSession` or `GameRoot`, not an uncontrolled proliferation of globals. `GameSession` provides typed references to its domain services. Each service mutates only its owned state through the shared transaction coordinator; cross-domain operations such as quest completion stage all changes and commit once.

### Events

EventBus broadcasts after successful mutations: `inventory_changed`, `equipment_changed`, `currency_changed`, `entity_defeated(entity_id)`, `evidence_acquired(evidence_id)`, `quest_updated(quest_id)`, `choice_committed(choice_id, value)`, `landmark_discovered(landmark_id)`, `save_completed(slot_id)`, `mode_changed(mode)`. Payloads contain stable IDs and value snapshots, not mutable node references. HUD listens; it does not decide outcomes. After loading, use one `session_restored` notification followed by quest reconciliation and UI refresh; do not replay rewards as if historical events were new.

### Collision and scene contracts

Name physics layers in project settings: 1 world, 2 player, 3 hostile_bodies, 4 neutral_bodies, 5 interactables, 6 hurtboxes, 7 triggers. Document exact masks in T02. Interactions raycast both world and interactables; world blocks farther objects. Attack queries select hostile hurtboxes and world occlusion, excluding the attacker and neutral actors. Discovery/hazard triggers do not physically obstruct movement.

`GameRoot` contains WorldRouter, Player, WorldContainer, GameModeController, HUD, and modal UI. The player persists across scene travel; world scenes do not instantiate duplicate players. Each world scene exposes a registry of entrance transforms, rest points, persistent entities, and navigation regions. Scene instantiation order is registry → apply saved entity state → synchronize navigation → place player → allow input.

### World construction and encounter manifest

Use authored deterministic height/mesh geometry and modular scenes. `tools/bake_world.gd` produces the same layout from the committed map manifest and fixed seed; runtime random generation does not decide story placements. Trees/rocks may be seeded decorative scattering outside reserved paths. Do not scatter collisions across entrances, objectives, or spawn points.

Required hostile spawn groups and counts:

| Group | Composition | Persistent purpose |
|---|---|---|
| south_cart | 2 cutpurses | Opening encounter |
| road_checkpoint | 3 levy spearmen | Toll pressure and ending aftermath |
| kiln_path | 2 cutpurses | SQ01 approach |
| medicine_cache | 2 deserter raiders | SQ06 supplies |
| east_path | 2 cutpurses | Optional route encounter |
| monastery_yard | 2 hollow keepers | Monastery approach |
| crypt | 4 hollow keepers | Vault route |
| watchtower | 2 deserter raiders + 1 cutpurse | Ledger and badge |
| castle_approach | 2 levy spearmen | Hostile private retainers, distinct from neutral courtyard wardens |
| undercroft | 2 levy spearmen + 1 deserter raider | Storehouse route |
| captain_hall | Captain Rusk | Boss |

Total **26 authored hostile spawns**: **7 cutpurses, 7 spearmen, 5 raiders, 6 hollow keepers, and 1 captain**. Derive and validate these counts from the composition rows in the content validator. Use stable entity IDs such as `south_cart_cutpurse_01`; a saved defeat refers to that entity ID, not its archetype or scene-tree name.

## D11. Persistence and state integrity

### Save format

Save one autosave and three manual slots under `user://saves/`. Settings live separately in `user://settings.json`. Each save envelope contains `schema_version=1`, exact game/content version, timestamp, slot metadata, checksum of canonical payload bytes, and `payload`. The checksum detects damage, not malicious tampering; no security claim is made.

Payload contains player health/stamina/crowns, equipment stack IDs, inventory stacks, key-item counts, acquired evidence IDs, quest states/objective records, choices, discovered landmarks, rest anchor, current world scene and safe transform, containers and remaining loot, defeated/disabled entity IDs, puzzle solved flag, shop equipment stock, completed transaction receipts (ID plus committed result summary), pending deliveries, and campaign ending. Store vectors as numeric arrays and rotations as explicit numeric values. Do not serialize the scene tree.

### Writing and loading

1. At a safe frame boundary, snapshot state after all committed transactions; validate its invariants.
2. Write a temporary file in the same directory, flush, close, read it back, and validate payload/checksum.
3. Preserve the previous valid slot as backup, then replace the destination using the safest same-filesystem rename supported by the target. Handle failed renames without deleting the only valid copy.
4. Only then report success and update slot metadata. On errors, retain gameplay state, show a useful message, and keep the last valid save.

Load into a detached candidate state, validate schema/types/IDs/counts/ownership and checksum, then construct the world and swap session state. If primary fails, offer its valid backup and clearly identify recovery. Never overwrite a corrupt or unsupported save merely by inspecting it. Future schema versions are rejected with a readable compatibility message. Schema migrations are not required until a second schema exists.

Save requests during combat, a transaction, scene travel, or active healing are refused or queued until safe; the UI explains why. Dialogue choices complete their transaction before an autosave request. Autosave triggers: completed quest/choice, activated rest point, safe scene transition, and completed death recovery. If a completed quest occurs while danger remains, queue its save; do not freeze combat or serialize halfway through an attack. The ending is saved in a safe mode before epilogue display.

Enemy partial health is not persisted. Living enemies restart at their authored spawns/full health on load. Dead actors stay absent or have loot-only corpse representations with remaining contents. The player loads at a validated safe anchor in the recorded scene, not necessarily their exact last combat position. Manual saves are only available outside danger and transitions; this behavior is disclosed in the save menu.

If the ending autosave fails, keep the already committed in-memory ending and present **Retry save** or **Continue without saving**, explaining the risk of losing that choice on exit. Only an explicit continue-unsaved action may bypass the normal save-before-epilogue rule. Retrying never reruns the ending transaction.

Coalesce deferred autosave requests into one pending request for the latest safe committed snapshot. Failed uncommitted actions do not create completed transaction receipts. Successful replay of an existing transaction ID returns its recorded result summary without applying effects or publishing mutation notifications again.

### Required invariants

- Currency and stack quantities are nonnegative integers, with valid stack limits.
- Equipped stacks exist, belong to the player, and fit the slot; at least one melee weapon is owned.
- Quest completion cannot precede satisfied predicates and can pay only once.
- Evidence acquisition survives key-item hand-in.
- An entity can be defeated once and looted incrementally without respawning its rewards.
- Exactly one final ending or `none` exists; shop modifiers derive from it.
- A pending delivery is either pending or claimed, never both.
- Interrupted saves leave at least one prior valid slot or a clearly reported first-save failure.

## D12. Budgets, validation, and delivery

### Performance design targets

Measure a release build on available hardware and record exact CPU/GPU/RAM/OS, renderer, resolution, settings, and sampling method. Target 60 FPS at default Retro settings on a representative integrated-GPU desktop/laptop; this is a target, not a verified minimum specification. Suggested reference class is Apple M1 8 GB or comparable integrated graphics, but do not claim that device was tested if it was not available.

Budget initially for ≤12 active thinking hostiles, with distant AI sleeping beyond 70 m; all persistent state still exists. Limit nearby shadow-casting directional light to one, unshadowed local lights to four affecting a view, visible triangles to roughly 250k, and active draw submissions to roughly 500 at default settings. These are diagnostic budgets; actual frame-time evidence decides acceptance. No runtime navigation rebake on every frame, repeated resource loading per attack, or unbounded event subscriptions.

### Verification strategy

Use a lightweight GDScript test runner extending SceneTree; no third-party testing addon is required. Unit tests target combat formulas/timers, inventory/economy transactions, quest predicates/reward idempotence, and save validation. Integration tests instantiate real scenes and exercise interaction occlusion, damage deduplication, navigation readiness, transitions, persistence, and the main-quest chain.

Automated story tests drive the same domain APIs used by UI; separate real-input playthroughs prove bindings, focus, navigation, readability, combat telegraphs, and spatial reachability. Debug grants/teleports may accelerate isolated tests but cannot substitute for an unassisted end-to-end campaign playthrough. Each ending gets a checkpoint fixture and a reload/aftermath test. At least one full main-campaign run and all six side quests must be verified in the playable build, with remaining branches covered from fixtures.

Tuning requires observation: opening duel, two-enemy fight, blocked doorway, large UI scale, and Rusk's two phases. Headless success proves no visual polish or combat feel by itself. If visual execution is unavailable, record the gate as unverified and provide exact reproduction steps; do not label the release complete.

### Release package

Source opens directly in the pinned Godot version. `README.md` contains installation/launch, controls, build instructions, test commands, save location, credits, and known limitations. Host-platform export runs without the editor or network. Export presets exist for Windows, macOS, and Linux; only actually executed exports receive verified status. macOS signing/notarization is not promised. Art/audio/font licenses and attribution are recorded in `docs/asset_manifest.md` and included with builds.

No automatic publishing, store submission, telemetry, cloud account, or online deployment is part of this specification. The game is finished locally when all mandatory requirements and release gates pass, not when a screenshot or title screen exists.

### Technical reference anchors

These sources establish supported engine workflows; the concrete mechanics above are original design choices. Check against the version pinned in T01 before implementation.

- [Godot command-line workflow](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html): headless operation, imports, scripts, and export commands.
- [Godot renderer overview](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html): renderer capabilities and limits.
- [Godot 3D asset formats](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html): glTF/GLB import and Blender integration.
- [Godot NavigationAgent guidance](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html): synchronization and navigation update behavior.
- [Godot save-game guide](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html): serialization building blocks; the stronger transaction/backup contract here must be implemented separately.
