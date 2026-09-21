# MIREWARD — Requirements and acceptance criteria

**Specification 1.0 · 21 September 2026**

Companion documents: [design.md](design.md) defines the game and shared interfaces; [tasks.md](tasks.md) defines implementation order and agent handoffs.

## Authority and verification language

Every requirement below is mandatory for the complete 1.0 release. “Shall” denotes an obligation. A “target” is a tuning/performance hypothesis and is identified as such. An implementation task may finish its bounded work before the release is complete, but the orchestrator may not call the whole game complete until every requirement has passing evidence. Missing execution capability is **UNVERIFIED**, never PASS.

Each requirement has a stable ID, relevant design sections, and acceptance criteria. Tasks map these IDs to one or more implementing owners and a final verification task. Record the mapping in the future repository's `docs/traceability.md` and retain evidence paths. This file defines desired behavior; it does not report tests already run.

Verification methods: **A** = automated domain/content test; **I** = real-scene integration test; **P** = playable input/visual/audio inspection; **E** = exported-build/environment inspection. Tests should exercise public behavior and failure cases, not merely assert constants equal themselves.

## Product and project foundation

### R01 — Complete bounded game

**Design:** D00, D07, D12. **Verify:** A, P, E.

The release shall provide the complete MIREWARD campaign and playable aftermath within the locked scope.

- The game contains six main quests, six side quests, eight named speaking characters, nine discoverable landmarks, 23 item definitions, four ordinary enemy archetypes, one boss archetype, and the 26 authored hostile spawns specified in D10.
- A new game can reach each of the three endings; all side quests remain completable afterward.
- No mandatory button, quest, combat system, or ending is a stub, TODO screen, nonfunctional placeholder, or instruction to finish the feature manually.
- The introductory slice alone does not satisfy this requirement.

### R02 — Reproducible engine and project

**Design:** D00, D10. **Verify:** A, E.

The project shall use one pinned stable Godot 4 version, typed GDScript, and the Compatibility renderer.

- `.godot-version`, README, actual executing engine, and export templates identify the same exact version.
- A fresh project import completes without missing resources, parse errors, or reliance on an author's absolute filesystem path.
- Required gameplay runs without C#, GDExtension, paid addons, Blender, or an API credential.
- A renderer-specific feature unavailable in Compatibility cannot be required for visibility, traversal, or progression.

### R03 — Offline operation and source availability

**Design:** D00, D12. **Verify:** E.

The runnable game shall need no account or network connection.

- After installation/import, disconnect networking and complete launch, a quest, save/load, and settings changes.
- Runtime contains no remote asset download, telemetry, remote AI, or authentication requirement.
- Source, required assets, settings defaults, and generation inputs are present in the repository.

### R04 — Shared contracts and validated data

**Design:** D10. **Verify:** A, I.

Modules shall communicate through the specified stable IDs, domain services, validated resources, and after-commit events.

- A validator rejects duplicate IDs, broken references, illegal enum values, missing dialogue destinations, missing objective targets, invalid loot, and absent scene entrances.
- Inventory/currency/quest/world mutations cannot be performed directly by UI handlers.
- Unknown content IDs cause an actionable validation/load error rather than silently producing a blank asset or invented item.
- Cross-domain transactions either commit all their changes or none, and their notifications follow the committed state.

## World, movement, and interaction

### R05 — Authored exterior and landmarks

**Design:** D02, D10. **Verify:** A, I, P.

The player shall traverse one coherent exterior containing the nine named landmarks and their connecting route loops.

- Landmarks match the design's geography and silhouettes; all can be reached with ordinary movement.
- Both side loops bypass the checkpoint; no currency or compulsory checkpoint kill is required to reach the monastery or castle courtyard.
- Castle and monastery silhouettes provide visual orientation from at least two authored viewpoints each.
- Quest markers, collision, and navigation use the same committed map manifest; regenerated terrain does not move required objects unpredictably.

### R06 — Interiors and scene travel

**Design:** D02, D10. **Verify:** I, P.

Doors shall connect the exterior with the inn, crypt, and undercroft using stable entrances and safe transitions.

- Enter and exit each interior ten times without duplicating the player, inventory, NPCs, signals, or loot.
- Transition locks input, fades, applies persistent world state, waits for navigation readiness, places the player safely, and returns control.
- The returned player does not overlap a door trigger, world collider, hostile, or floor.
- Early undercroft access is visibly blocked until MQ05's evidence handoff; the exterior courtyard remains explorable.

### R07 — First-person locomotion

**Design:** D03. **Verify:** I, P.

The player shall walk, sprint, jump, and look using a collision-aware first-person controller.

- Flat-ground speed and normalized diagonal movement match the configured values within 5% across 30/60/120 render-FPS settings, using fixed physics timing.
- Sprint costs stamina only while moving; at zero stamina it becomes walking without trapping input.
- Jump requires grounding and sufficient stamina; repeated air-jump input never adds a second impulse.
- Mouse pitch stays within limits, slopes obey the configured floor limit, and the capsule cannot pass through walls at sprint speed.

### R08 — Input, remapping, and focus

**Design:** D03, D09. **Verify:** A, I, P.

Every digital gameplay action shall be remappable, with persistent mouse settings and coherent UI focus.

- Remap attack, interact, and inventory; prompts and gameplay reflect the new bindings after reload.
- Conflicts offer swap/cancel, and Escape/back remains a usable route out of menus.
- Losing window focus pauses active gameplay and clears buffered input edges.
- Clicking UI, closing a menu while holding attack, or returning from another application never causes an unintended fresh attack or interaction.

### R09 — Contextual interaction

**Design:** D03, D10. **Verify:** I, P.

The player shall interact once per press with the closest eligible visible object within 2.5 meters.

- A closed wall/door blocks a container or NPC behind it, even when the target trigger is oversized.
- Holding E produces one activation; separate presses produce separately validated actions.
- An unavailable action displays its reason, including a locked undercroft or unsafe rest point.
- A stale offer is revalidated when committed; opening another panel cannot bypass changed conditions.

### R10 — Discovery, map, and objective direction

**Design:** D02, D07, D09. **Verify:** A, I, P.

Discovering a landmark shall persist it on the map and support useful objective guidance.

- Exactly the nine authored landmark IDs are discoverable, each once; discovery survives save/load.
- The map shows player position, discovered names, and the tracked objective without exposing undiscovered named landmarks.
- An interior objective points to its exterior entrance when the player is outside.
- Every active quest has a useful next-action text and location hint; discovery is not required to understand the main route.

### R11 — Hazards and safe recovery

**Design:** D04, D10. **Verify:** I, P.

Deep water, exterior bounds, and invalid positions shall recover the player to a validated safe anchor.

- Falling from each perimeter test point and entering deep water returns the player without an endless recovery loop.
- Recovery removes 10 HP but leaves at least 1 HP, retains items/quests, and does not apply the death currency penalty.
- Recovery during Rusk's live encounter resets the living boss and opens the combat gate; it does not grant victory.
- Invalid or missing local safe anchors fall back to the village shrine and record a diagnostic.

## Combat and enemies

### R12 — Attack phases and stamina

**Design:** D04. **Verify:** A, I, P.

Light and heavy attacks shall follow windup, active, and recovery phases with one stamina deduction.

- All four weapons use their configured light profile and the specified heavy multipliers/timing.
- Damage can occur only in the active phase; insufficient stamina produces no attack or partial deduction.
- At most one follow-up attack is buffered in the allowed window; rapid input does not queue an unlimited combo.
- Guard, heal, equip, and UI transitions do not cancel committed costs or shorten a recovery phase.

### R13 — Spatial hit validation

**Design:** D04, D10. **Verify:** A, I, P.

Melee damage shall require a valid swept contact within reach and an unobstructed path.

- A test swing hitting the same victim over multiple physics frames applies damage once.
- Two victims intersecting a swing receive at most one total victim hit, selected by nearest valid swept contact.
- A victim behind a wall or outside reach receives no damage.
- Neutral/civilian actors and the attacker cannot receive this combat damage; dead actors reject later damage.

### R14 — Shield direction and ordinary block

**Design:** D04. **Verify:** A, I, P.

Guard shall mitigate attacks only within the specified frontal cone and with sufficient stamina.

- Front, ±60° boundary, and rear fixtures verify the directional rule without dependence on camera pitch.
- Ordinary block uses shield cost multiplier, 10% health pass-through, then armor and final rounding.
- A 20-damage front hit into a wooden shield consumes 16 stamina; with no armor it loses 2 HP.
- A rear hit ignores shield mitigation, and switching shield changes guard cost according to its definition.

### R15 — Parry and guard break

**Design:** D04. **Verify:** A, I, P.

Timed guard shall support a perfect parry and exhausted guard shall break predictably.

- A legal hit inside the 0.18 s window costs 5 stamina, loses zero HP, and staggers the attacker 0.65 s.
- Outside-window, rear, cooldown-ineligible, and insufficient-5-stamina cases do not parry.
- Holding or rapidly toggling guard cannot repeatedly reset a legal parry window inside its 0.65 s cooldown.
- With insufficient ordinary-block stamina, stamina reaches zero, half raw damage passes to armor, and attack/block stay disabled for 0.9 s.

### R16 — Damage, armor, and death signals

**Design:** D04, D05. **Verify:** A, I.

Health damage shall use the single authoritative combat calculation and death shall emit once.

- Heavy multipliers apply once before shield/armor, never again at the victim.
- Tests cover all armor reductions, minimum non-parry damage, perfect zero-damage parries, and player 0.20 s damage immunity.
- A second hit rejected during immunity does not extend immunity; expiry allows damage again.
- Multiple same-frame lethal requests create one death event, one persistent defeat, and one loot source.

### R17 — Healing and resource recovery

**Design:** D04, D05. **Verify:** A, I, P.

Consumables and stamina regeneration shall honor action timing, resource caps, and interruption rules.

- A consumable is charged only upon successful completion; damage or death interrupts it without consumption.
- Healing cannot start when its affected resource is full, during a committed attack, or during another consumable action.
- Restoring a resource never exceeds its maximum; repeated Q presses cannot consume stacked bandages instantly.
- Pausing suspends the timer; taking damage on the completion physics tick cancels before the heal commits.
- Stamina delay and suspended-regeneration states match the design.

### R18 — Four ordinary enemy archetypes

**Design:** D04, D10. **Verify:** A, I, P.

Cutpurse, levy spearman, deserter raider, and hollow keeper shall have distinguishable models, attacks, and configured stats.

- Archetypes and spawn composition match the manifest; no generic stationary damage cube substitutes for an enemy.
- Deserters guard according to their cadence and resource rules; keepers advertise their slow windup.
- Each supports idle/patrol, alert, chase, attack phases, stagger, return, and terminal death.
- Each drops exactly its authored loot and cannot be farmed by leaving, resting, or reloading.

### R19 — Perception and navigation

**Design:** D04, D10. **Verify:** I, P.

Hostiles shall perceive through explicit range/cone/occlusion checks and navigate valid scene geometry.

- A wall prevents sight and proximity detection; a clear approach triggers alert/chase.
- Losing sight and leaving leash range trigger the documented return behavior.
- Navigation never queries an unsynchronized map or repeatedly rebakes the world during play.
- A blocked route triggers bounded recovery without a visible teleport, infinite error spam, or walking through collision.
- Changing scenes removes old navigation targets and leaves no stale player reference.

### R20 — Encounter fairness and combat feedback

**Design:** D04, D08. **Verify:** I, P.

Combat shall expose readable telegraphs, controlled crowd pressure, and distinguishable outcomes.

- At most two enemies hold player attack reservations, with required windup-start separation.
- Interrupted/dead attackers release reservations; a lone enemy is not permanently prevented from attacking.
- Normal hit, block, parry, guard break, and death each have distinct visual feedback and a matching sound when effects audio is enabled.
- At default retro resolution, testers can identify windup versus recovery without reading a debug overlay.

### R21 — Captain Rusk encounter

**Design:** D04, D07. **Verify:** A, I, P.

Rusk shall provide the specified two-phase, fully completable final duel.

- The duel begins only after the explicit challenge and closes its combat gate.
- Thrust/sweep alternate, both can be parried, and the half-health phase line/stance occurs once.
- Phase two shortens recovery by 15% while preserving telegraphs and damage windows; the breath opening occurs after every two attacks.
- Victory unlocks the seal chest and gate once; death/recovery/load resets a living Rusk and never grants the seal.
- Defeated Rusk stays defeated after reload and scene travel.

### R22 — Player death and rest

**Design:** D04, D11. **Verify:** A, I, P.

Death and resting shall preserve permanent progress while restoring the player according to their separate rules.

- Death charges `min(12, floor(crowns × 0.10))` once, then respawns at the activated rest anchor with full resources.
- Inventory, quest/evidence state, defeated enemies, containers, and pending rewards remain intact.
- Free outdoor rest and paid/free inn rest behave correctly; unsafe rest is refused without charging money.
- Living encounters reset on rest; defeated enemies and their remaining corpse loot do not duplicate.
- The new game's preactivated village shrine ensures a valid first-death destination.

## Inventory, economy, and progression

### R23 — Item registry and starting loadout

**Design:** D05. **Verify:** A, I.

The item registry and a new character shall match the specified content and equipment baseline.

- Exactly 23 distinct item definitions exist with valid category, icon, description, stack limit, and behavior fields.
- New game grants 12 crowns, three equipped starting gear pieces, two bandages, and one bread exactly once.
- Opening/closing menus or reentering the world does not rerun starting grants.
- Unknown IDs, negative counts, and wrong-slot equipment are rejected.

### R24 — Capacity, equipment, and key items

**Design:** D05. **Verify:** A, I, P.

Normal inventory shall have sixteen slots and key items shall remain separate and protected.

- Existing consumable stacks fill before new slots; stacks cannot exceed ten.
- Equipped items occupy their normal slots and use valid owned stack IDs.
- Equipment cannot change during a committed attack/heal or while the game is in a forbidden transition.
- Quest/evidence items cannot be sold/discarded or blocked by a full normal inventory.
- The player cannot sell the final owned melee weapon.

### R25 — Persistent loot and pending rewards

**Design:** D05, D11. **Verify:** A, I, P.

Loot and quest rewards shall survive partial pickup, full capacity, and reload without loss or duplication.

- A full inventory leaves ordinary loot in its container and reports capacity failure.
- Partial loot collection persists exactly the remaining quantity across travel/load.
- A quest reward that does not fit appears in pending deliveries while currency and story completion still commit.
- Claiming a pending delivery twice grants once; a failed capacity check leaves it pending.
- Corpse loot contains the enemy's gold only once; no separate automatic duplicate payment occurs.

### R26 — Shop transactions

**Design:** D05. **Verify:** A, I, P.

Buying and selling shall atomically validate money, stock, capacity, ownership, and equipment restrictions.

- A failure changes neither crowns, stock, nor inventory.
- Repeated submission of a successfully committed transaction ID has the original outcome without repeating its effects; separate deliberate purchases use distinct IDs. Failed, uncommitted attempts do not reserve a completion key or block a later valid retry.
- Prices match ending multipliers and sell rules, with no buy/sell arbitrage for any item or ending.
- Oswin's equipment stock is finite; Tamsin's consumable availability is unlimited; sold equipment does not recreate store stock.
- Displayed price and actual charge agree, including after an ending and reload.

### R27 — Viable equipment progression

**Design:** D04, D05, D07. **Verify:** A, P.

Equipment progression shall have observable gameplay and presentation effects while keeping the campaign possible without money.

- All four swords, both shields, and three armor tiers can be obtained through their stated sources.
- Equipping changes actual damage/guard/armor values and the relevant first-person gear appearance.
- SQ01 supplies the Arming Sword, SQ05 the Kite Shield, and MQ05 the Watchblade with overflow handling.
- A zero-crown fixture can reach all required main objectives, rest for free, and finish the campaign.

## Quests, narrative, and endings

### R28 — Data-driven quest state

**Design:** D07, D10. **Verify:** A, I.

Quests shall use validated definitions, explicit states, predicate-based objectives, and persistent reconciliation.

- State transitions obey prerequisites; LOCKED quests cannot be completed directly through UI.
- Activating or loading a quest reevaluates existing evidence, defeated entities, solved puzzles, and collected items.
- Objective counts are bounded, completed progress is monotonic, and duplicated events cannot inflate counters.
- A fresh player never sees an empty active objective or an impossible next step.

### R29 — Six-main-quest sequence

**Design:** D07. **Verify:** A, I, P.

The campaign shall implement the exact objective chain, rewards, and unlocks of MQ01–MQ06.

- Bread and Iron requires cart recovery/return; King's Due requires notice and receipt; A Bell Without a Rope requires Elian, puzzle, charter, and attestation.
- Names in the Ledger requires Wren, ledger, terms choice, and Mara report; A Debt in Stone requires Ada, duel, seal, and Ada report.
- The Last Toll requires the writ-table review and explicit irreversible confirmation.
- Rewards and retained/consumed evidence match D07; UI and domain-level completion agree.
- An unassisted new-game playthrough reaches an ending using actual movement and interactions.

### R30 — Six side quests

**Design:** D07. **Verify:** A, I, P.

All six side quests shall implement their named giver, physical objectives, rewards, and durable consequences.

- Each can be accepted, tracked, advanced, turned in, and reviewed as completed.
- The three candles are distinct persistent entities; revisiting one cannot satisfy the remaining count.
- SQ02 changes future inn costs, SQ04 lights the shelter, and SQ05 restores Ada's visible badge.
- SQ06 commits exactly one medicine recipient and one 10-crown reward.
- Side quests are available after each ending and do not consume main-story medicine/evidence.

### R31 — Bell puzzle

**Design:** D07. **Verify:** A, I, P.

The crypt puzzle shall open its vault only through the specified readable three-step sequence.

- Reed, stone, flame in that order solves it; incorrect input resets without damage or permanent lockout.
- Text labels and a nearby clue make the solution available without hearing audio or distinguishing colors.
- Solved state survives reload; partial progress restarts at zero.
- Solving before MQ03 remains valid when MQ03 activates, and collecting the charter is tracked separately.

### R32 — Dialogue and cast

**Design:** D06, D07, D09. **Verify:** A, I, P.

The eight named speakers shall provide the required dialogue, quest options, and contextual reactions.

- Canonical lines/information and material choices from D06/D07 are implemented; no lorem ipsum or inaccessible dialogue nodes remain.
- Relevant turn-ins take priority over ordinary greetings without hiding shops, rest, or unrelated quests.
- Leaving dialogue has no unconfirmed effects; choosing a stale/unavailable option is rejected safely.
- NPCs remain at their stated stations and essential noncombat speakers cannot be killed or permanently made unavailable.
- Rusk's dialogue transitions into combat only through the explicit challenge.

### R33 — Evidence and early collection

**Design:** D06, D07, D11. **Verify:** A, I.

Evidence and quest objects acquired out of order shall remain usable and understandable.

- Acquire charter, ledger, hammer, badge, and candles before their quests, then accept quests and complete their remaining steps.
- Handed-in key objects retain acquisition history; opening a completed readable never pays a reward.
- Critical documents remain readable in the journal after relevant handoffs.
- Destroying/moving physics props or missing enemy loot cannot destroy mandatory evidence; story items use fixed persistent sources.

### R34 — Atomic choices and rewards

**Design:** D05, D07, D10, D11. **Verify:** A, I.

Quest completion and branch choices shall be atomic, idempotent, and durable.

- Simulate repeated clicks, duplicate event delivery, reload after completion, and two same-frame turn-in requests; each pays once.
- Failure before commit consumes no quest object and applies no choice/reward; success commits all related effects together.
- Choosing Wren's terms sets one valid enum and preserves the same main-story access/reward.
- Camp-versus-village medicine cannot be delivered twice through separate NPCs.

### R35 — Three final resolutions

**Design:** D07. **Verify:** A, I, P.

The writ table shall present and commit exactly one of charter, warden, or free_road.

- Each choice shows its narrative/systemic consequences before confirmation; cancel returns without mutation.
- Completing one ending locks further ending changes and sets the correct shop multiplier, banners/signs, and checkpoint actor behavior.
- Dead checkpoint guards stay dead; charter/warden only change surviving actors, and free_road disables the checkpoint spawns.
- Ending commit saves successfully before epilogue display; on save failure present retry/continue-unsaved explicitly, retaining the committed session without applying it twice.

### R36 — Epilogue and continued play

**Design:** D07, D09. **Verify:** A, I, P.

The ending shall present three coherent text panels and permit continued play or return to title.

- Text reflects the chosen resolution, Wren terms, and medicine result, including the incomplete-side-quest variant.
- Return to valley restores functional movement, menus, shops, side quests, and remaining loot.
- Loading a completed save preserves aftermath and does not re-award anything or force the epilogue again.
- Journal replay uses current side-quest flags without changing the locked ending or replaying transactions.

## Persistence and failure recovery

### R37 — Save payload and slots

**Design:** D11. **Verify:** A, I, P.

The game shall provide one autosave, three manual slots, and separately persisted settings.

- Payload covers every field listed in D11, uses schema/content versioning, and contains no object pointer or scene-tree index as persistent identity.
- Save→load round-trips inventory, equipment, key items, evidence, quests, choices, world state, remaining loot, stock, pending rewards, and ending.
- Player position restores to a safe recorded-scene anchor; living enemies reset, defeated enemies do not.
- Slot UI reports chapter, location, and timestamp; empty/invalid slots do not crash Continue.

### R38 — Safe writes and corrupt-save recovery

**Design:** D11. **Verify:** A, I.

Interrupted or invalid writes shall not silently destroy the last valid save.

- Inject failures at temporary write, validation, backup, and replacement stages; preserve a prior valid file or clearly report a failed first save.
- Validate checksum, schema, numeric ranges, IDs, item ownership, and quest/ending consistency before session replacement.
- A corrupt primary with a valid backup offers identified recovery; both invalid files produce a useful error without destroying either.
- Unsupported future schemas are rejected; inspecting them never overwrites them.

### R39 — Safe save timing and load isolation

**Design:** D11. **Verify:** A, I, P.

Saving/loading shall occur at valid state boundaries and explain deferred or refused actions.

- Combat, healing, travel, and in-flight transactions cannot be serialized midway through mutation.
- Quest/choice autosaves requested during danger queue until safe, and the ending uses the explicit failure behavior in R35.
- Loading a malformed candidate leaves the current session playable and unchanged.
- Successful load restores the world, reconciles quests, refreshes UI, and clears stale combat/modal input without replaying reward events.

### R40 — Lifecycle and new-game isolation

**Design:** D09, D10, D11. **Verify:** A, I, P.

Starting, loading, and leaving sessions shall release old runtime state and protect saved progress.

- New Game resets every session-owned quest/choice/entity/transaction field and retains user settings.
- New Game confirms replacement of an existing autosave and never silently destroys manual slots.
- Continue selects the newest valid slot by saved timestamp; invalid newer slots are skipped with a notice.
- Repeated title→new/load→title cycles leave no duplicated autoload listeners, playing ambience, player nodes, or quest notifications.

## Presentation and usability

### R41 — Cohesive final visual assets

**Design:** D08. **Verify:** A, P.

Characters, gear, environments, and props shall form a consistent low-poly medieval presentation.

- Required asset families and animations from D08 are present, with recognizable knight anatomy and distinct enemy silhouettes.
- First-person weapon/armor visuals correspond to equipped gear and combat timing.
- Story containers, chimes, rest points, and interactable doors are visually distinguishable from scenery.
- Graybox geometry, debugging capsules, missing textures, development labels, and placeholder portraits are absent from the release path.
- Original procedural assets qualify when they satisfy these visual criteria; a purchased/imported pack is not required.

### R42 — Retro/native rendering and settings

**Design:** D08. **Verify:** I, P.

The game shall render a coherent 3D view in both Retro and Native modes with independent sharp UI.

- Retro uses the defined 540-pixel-high aspect-correct view; Native uses window resolution.
- Resizing and switching modes preserve aspect, crosshair/raycast alignment, mouse sensitivity, and UI focus.
- Fog and lighting make critical routes/telegraphs visible; Compatibility-specific limitations do not produce missing effects or black materials.
- Shadows, VSync, display mode, bob, shake, and vertical FOV settings apply and persist without restarting a quest.

### R43 — Soundscape and audio controls

**Design:** D08. **Verify:** A, P.

The required gameplay cues, ambient zones, UI sounds, and original/licensed music bed shall be implemented.

- All required sound events resolve to actual audible assets and the intended bus.
- Entering an interior replaces/crossfades exterior ambience without stacking endless loops.
- Master and each bus can be muted independently and persist across restart.
- Paused gameplay audio follows pause policy while UI feedback remains audible; critical cues retain a visual equivalent when muted.

### R44 — HUD, inventory, journal, and map

**Design:** D09. **Verify:** I, P.

The player shall understand current resources, equipment, objectives, and interactions without a developer overlay.

- Health/stamina/currency/equipment update after transactions, damage, consumption, and load.
- Inventory displays capacity, item details, equipment, key items, and pending rewards with valid actions.
- Journal shows active/completed quests, objective counts, clues, important documents, and epilogue replay when unlocked.
- Map, compass, and context prompts provide actionable navigation and never obscure mandatory controls.
- Rusk's boss bar exists only during the duel; ordinary enemy health follows the targeting/recent-hit rule.

### R45 — Menus and modal ownership

**Design:** D03, D09, D10. **Verify:** I, P.

One mode controller shall manage pausing, input ownership, cursor state, and modal transitions.

- Title actions, pause actions, inventory, journal, map, dialogue, shop, settings, death, and epilogue can all be entered/exited through real inputs.
- Gameplay timers and movement freeze during modals; resuming does not skip attack, heal, or puzzle timing.
- Nested confirmation panels return to the correct parent; Escape never leaves the player permanently paused or mouse-unlocked.
- Opening one gameplay menu closes/replaces another coherently rather than layering competing input handlers.

### R46 — Readability and accessibility options

**Design:** D03, D08, D09. **Verify:** P.

Menus and gameplay information shall remain usable with scaled text, muted sound, and disabled camera motion.

- At 1280×720, text scales 100/125/150% keep essential controls available through layout/scrolling, with no unreadable clipped quest choices.
- Keyboard focus is visible; mouse and keyboard can complete every menu operation.
- Color is not the sole cue for puzzle order, completion, item categories, or hostility.
- Invert-Y, sensitivity, FOV, zero bob, and zero shake work independently.
- Crucial narrative information is available as text and all puzzle instructions survive complete muting.

### R47 — Onboarding and feedback

**Design:** D02, D03, D05, D09. **Verify:** P.

The opening shall teach enough to reach and complete the cart contract without external instructions.

- Movement/look, interaction, combat, healing, journal, and map are introduced by brief dismissible contextual hints.
- The optional dummy teaches block/parry without awarding money or affecting story progression.
- Capacity, insufficient stamina, insufficient money, unavailable save/rest, quest readiness, and pending reward states give plain-language feedback.
- Hints do not repeat indefinitely after completion or cover combat telegraphs.

## Performance, validation, and delivery

### R48 — Bounded runtime and performance evidence

**Design:** D10, D12. **Verify:** A, I, P, E.

The implementation shall avoid unbounded runtime work and provide a measured performance report.

- Active hostile thinking is capped at twelve; distant AI sleeps/reactivates without losing permanent state.
- Navigation replanning, resource loads, event listeners, effects, and corpse/loot nodes remain bounded through a 20-minute mixed traversal/combat/menu soak.
- On the documented test host at default Retro settings, after warmup, target median frame time ≤16.7 ms and 95th percentile ≤33.3 ms across village, forest, crypt, and boss samples. Record sample length and actual results; failure requires optimization or an explicitly unmet gate.
- Loading each scene target ≤5 seconds on the documented host; unexplained stalls, growing memory after repeated travel, and repeated runtime errors fail regardless of average FPS.
- No claim of verified performance on hardware that was unavailable.

### R49 — Automated correctness and content checks

**Design:** D10–D12. **Verify:** A, I.

The repository shall contain runnable meaningful tests for its consequential state and integration behavior.

- The documented test command exits nonzero on failed assertions and identifies the requirement/fixture.
- Coverage includes spatial hits, combat formulas/timers, transactions, duplicate rewards, early collection, all ending branches, partial loot, save failure/recovery, modal input, and scene travel.
- Content validation verifies counts, registry links, dialogue graphs, objective targets, and scene entrance IDs.
- Domain tests are supplemented by real-scene integration tests; direct state injection alone does not prove a playable campaign.

### R50 — Playable end-to-end release gate

**Design:** D12. **Verify:** P, E.

The release shall be exercised through actual gameplay, not solely headless scripts or debug grants.

- Record one full new-game-to-ending playthrough and completion of all six side quests using normal movement, interaction, combat, and UI.
- From legitimate checkpoint fixtures, verify the other two endings, reload, and their visible aftermath.
- Inspect screenshots or captured frames for title, village, forest fight, crypt puzzle, inventory, large text, boss, and ending.
- Record blocking issues, fixes, rerun evidence, and any unverified gate. Missing GPU/input capability leaves this gate unverified.

### R51 — Export and documentation

**Design:** D12. **Verify:** E.

The final handoff shall include reproducible source, a tested host-platform export, and clear operating instructions.

- A fresh checkout/import launches; the host export launches independently of the editor and passes a short save/load/gameplay smoke test offline.
- Windows, macOS, and Linux export presets exist; verification status for each is accurate and host signing restrictions are disclosed where applicable.
- README covers engine version, opening/running, controls, tests, export steps, save paths, accessibility, credits, and known issues.
- No secrets, machine paths, `.godot/` import cache, or unnecessary generated builds are committed to source control.

### R52 — Licensing and honest completion

**Design:** D08, D12. **Verify:** A, E.

Every shipped asset shall have recorded provenance and completion reports shall reflect actual evidence.

- `docs/asset_manifest.md` identifies each asset family/file group, source or generation script, author, license, modifications, and required attribution.
- External assets with unknown or incompatible rights are replaced with original assets before release.
- No implementation report labels unrun tests PASS, headless execution visual verification, or an unavailable platform export verified.
- Required unfinished functionality is reported as an unmet requirement; it is not relabeled “future work” to close the project.

## Acceptance scenarios for the integrator

These combine requirements across modules. Keep their IDs in test reports; individual requirements remain authoritative.

| Scenario | Procedure | Required result |
|---|---|---|
| S01 — Honest first journey | New game; meet Mara; use default controls; recover cart supplies; return | MQ01 complete, exactly 18 crowns and one reward bandage added, MQ02 available, functioning save |
| S02 — The early explorer | Visit crypt/watchtower before story assignment; solve puzzle, collect charter/ledger/badge | Later quests recognize evidence, still require conversations/choices, and cannot deadlock |
| S03 — Full pockets | Fill all 16 slots, then finish SQ01 and MQ05 | Main state/currency commit; gear appears once in pending deliveries and can be claimed later |
| S04 — Fast fingers | Submit a turn-in/medicine choice twice, including two same-frame requests | One reward, one consumption, one branch; no partial state |
| S05 — Interrupted knight | Save before a quest; cause save-write failure after completion; retry | Prior save valid; current state retained; retry cannot repeat reward |
| S06 — Broken record | Corrupt primary autosave with valid backup; inspect and load | Recover with explicit notice, preserving corrupt file and manual slots |
| S07 — No money | Set a legitimate test state to zero crowns; retain starting gear | All mandatory routes, free rest, and main objectives remain available |
| S08 — The last toll, three times | Branch from pre-ending checkpoint into each resolution; reload | Exact flags, prices, signs, survivor reactions, and epilogue; no new enemies/rewards |
| S09 — The distracted player | Hold attack, open UI, alt-tab, return, close UI | Paused timers, correct cursor, no stray attack or stuck movement |
| S10 — A long wet walk | Twenty-minute scene/route/combat/menu loop | No lost references, multiplying ambience/listeners, missing entities, or unbounded runtime growth |
| S11 — Dead captain, live world | Defeat Rusk; leave before looting; reload; return | Rusk stays dead; seal chest remains available; MQ05 remains completable |
| S12 — Small screen | 1280×720, 150% text, muted audio, no bob/shake | Main story, puzzle, shops, confirmations, and ending remain usable |

## Completion statuses

Use **NOT STARTED**, **IN PROGRESS**, **PASS**, **FAIL**, or **UNVERIFIED** in `docs/traceability.md`. Each PASS points to test output, a reproducible playthrough note, or an inspected artifact. A task checkbox is not evidence by itself. A release with any FAIL or UNVERIFIED mandatory requirement must be described as an implementation candidate with named remaining gates, not a completed game.
