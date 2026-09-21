# MIREWARD — Codex implementation plan

**Specification 1.0 · 21 September 2026**

Read [requirements.md](requirements.md) for obligations and [design.md](design.md) for canon, tuning, data, and interfaces. This file is an execution contract for an orchestrating Codex agent and a sequence of focused subagents. The user supplies the specification once; the orchestrator carries the implementation through the queue, verifying each handoff. “One shot” means one complete initial brief and sustained execution, not a promise that the first generated code will work without iteration.

## How to launch the build

Place these three files in `specs/` inside a new game repository. Use the following kickoff prompt with Codex in that local repository:

```text
Build MIREWARD from specs/design.md, specs/requirements.md, and specs/tasks.md.
Treat the full specification as the authorized scope, including the complete
campaign, six side quests, three endings, saved aftermath, art, audio, tests,
and a host-platform release build.

Act as the integration lead. Read all three files first. Execute tasks T01
through T28 in order, with one focused implementation subagent active at a
time. Give each agent its exact task card, referenced design sections,
requirement IDs, current interfaces, and predecessor handoffs. If subagents
are unavailable, perform the same task sequence yourself.

Integrate and verify each task before dispatching the next. Fix failures
within the current task rather than accumulating disconnected partial
systems. Keep progress, decisions, traceability, and evidence in the repo.
Use the specified dependency-free asset baseline and first-person Godot
architecture. Do not replace the project with a browser mockup, title screen,
or combat demo. Do not silently omit mandatory features.

Continue autonomously through implementation and verification. Resolve
ordinary details using the specification and log your choice. Escalate only
a genuine contradiction affecting product behavior or an unavailable action
that prevents further authorized work. Do not spend money or publish the
game. Respect the actual tool permissions in this environment.

Before declaring the game complete, pass every mandatory release gate.
Report unrun checks as UNVERIFIED, not PASS. The final report must identify
the runnable source, tested build, launch instructions, tests actually run,
and any remaining failed or unverified requirement.
```

The specification author has made the camera, engine family, content scope, and gameplay choices. The implementation lead should not restart product discovery or ask the user to choose between engines, perspectives, or placeholder art workflows.

## Execution rules for the orchestrator

1. **One writer at a time.** This plan is sequential by default. Different task cards may own the same file at different times; that is intentional. Do not run overlapping implementation agents concurrently.
2. **Give context, not just a title.** Send the complete task card, its design sections, requirement text, current contract definitions, and relevant prior handoffs. A fresh agent cannot infer architecture from its task name.
3. **Preserve contracts.** Freeze public types, service APIs, InputMap IDs, collision layers, and content IDs in T02. Agents implement against them. If a change is necessary, the integration lead updates all affected consumers/tests/spec entries in the same integration before continuing.
4. **Keep an executable project.** Each task ends with successful import/parse and the narrow tests appropriate to its changed behavior. A test arena or fixture is acceptable before world integration; a broken main project is not an acceptable handoff.
5. **Review the actual work.** Read the diff, inspect task evidence, run meaningful checks, and confirm acceptance criteria. A subagent's assertion is a lead, not proof.
6. **Protect the user's work.** Start from the current repository state, preserve unrelated changes, and make reversible checkpoints. Use isolated branches/worktrees only if useful. Do not force-reset unrelated files or publish remotely.
7. **No invented execution.** If the engine, display, input automation, export templates, or target OS is unavailable, keep building what can be built and mark the corresponding verification blocked/unverified. Never simulate a successful command report.
8. **Finish the full queue.** T16 is an early integration gate. It is not a scope reduction. T28 is a complete release candidate only if all mandatory gates pass.
9. **Stop optional expansion.** No networking, horses, crafting, procedural continents, spell system, or new quest count. Use extra effort to remove defects and improve the specified presentation.

### Progress and resumption

In T01 create `docs/progress.md`, `docs/decisions.md`, `docs/traceability.md`, `docs/verification.md`, and `docs/handoffs/`. Progress records task ID, status, last checkpoint, evidence, and exact next action. Handoffs list changed files, APIs, tests run, known issues, and successor advice. On resumption, read those records and inspect the repository before deciding whether to rerun a task. Do not repeat completed asset generation or purchases/downloads unnecessarily.

Task status is `NOT_STARTED`, `IN_PROGRESS`, `IMPLEMENTED`, `VERIFIED`, or `BLOCKED`. IMPLEMENTED means source exists but verification remains; only VERIFIED closes the task gate. An environment-blocked visual gate can remain BLOCKED while independent tasks continue, but final completion remains blocked.

### Subagent dispatch template

```text
TASK: Txx — <title>
OBJECTIVE: <exact task card>
READ FIRST: <D sections, R IDs, public contracts, predecessor handoffs>
DEPENDENCIES: <verified tasks, or documented source-only prerequisites>
OWNED FILES: <task paths; notify the lead before changing other contracts>
DO: Implement the card, run its focused checks, fix defects, update the
task handoff, and return concrete evidence.
DO NOT: Change product scope, rename shared IDs, overwrite unrelated work,
or report unexecuted tests as passing.
HANDOFF: Changed paths; behavior now working; commands and results;
screenshots if relevant; unmet criteria; contract changes proposed;
next integration step.
```

### Standard verification commands

Use the absolute path of the version-pinned Godot executable where `godot` is not on PATH. These are command templates, not claims of execution:

```bash
godot --version
godot --headless --path . --import
godot --headless --path . --script res://tools/validate_content.gd
godot --headless --path . --script res://tests/run_all.gd
godot --path .
```

T02 provides the validator and test-runner entry points, initially with minimal checks; every later task extends meaningful coverage where needed. The runner must return a nonzero process exit code on failure. Headless tests use dedicated temporary save paths and never overwrite real user slots. Validate command availability against the pinned engine's `--help`. Host export commands and exact preset names are established in T28.

## Ordered task index

Dependency lists identify minimum technical prerequisites. Execute in numerical order so content and integration context stay predictable. Every dependency must have usable verified interfaces; an honestly documented unavailable runtime gate does not justify pretending it passed.

| Task | Deliverable | Depends on | Main requirement ownership |
|---|---|---|---|
| T01 | Project, environment, and execution records | None | R02, R03, R51 |
| T02 | Shared contracts, registries, and test harness | T01 | R04, R23, R49 |
| T03 | Baseline visual asset toolkit | T02 | R41, R52 |
| T04 | Player movement, camera, and input | T02, T03 | R07, R08 |
| T05 | Interaction and mode controller | T04 | R09, R45 |
| T06 | Player combat and damage resolver | T02, T04, T05 | R12–R16, R20 |
| T07 | Ordinary enemies and navigation | T03, T06 | R18–R20 |
| T08 | Inventory, equipment, and loot | T02, T05, T06 | R23–R25, R27 |
| T09 | Shops, healing, and rest/death services | T07, T08 | R17, R22, R26, R27 |
| T10 | Exterior terrain, route topology, and map manifest | T03, T05, T07 | R05, R10, R11 |
| T11 | Interiors, transitions, and recovery | T09, T10 | R06, R11 |
| T12 | Quest engine and all quest definitions | T02, T08, T09 | R28, R33, R34 |
| T13 | Dialogue engine and character content | T05, T12 | R32, R34 |
| T14 | Save/load, settings persistence, lifecycle | T09, T11, T12, T13 | R37–R40 |
| T15 | Functional game UI and onboarding | T10, T13, T14 | R10, R44–R47 |
| T16 | Verified opening adventure | T06–T15 | R01, R29, R47, R50 |
| T17 | All exterior landmarks, NPCs, and encounters | T10, T11, T16 | R05, R10, R18, R32, R41 |
| T18 | Toll investigation, crypt, and MQ02–MQ03 | T12–T17 | R29, R31, R33 |
| T19 | Camp, watchtower, and MQ04 | T17, T18 | R29, R32–R34 |
| T20 | Castle, Rusk, and MQ05 | T07, T14, T19 | R21, R29, R33 |
| T21 | Six complete side quests | T17, T19, T20 | R25, R27, R30, R33, R34 |
| T22 | MQ06, three endings, and aftermath | T14, T20, T21 | R26, R29, R35, R36 |
| T23 | Final art, animation, and rendering pass | T03, T17–T22 | R20, R41, R42 |
| T24 | Complete soundscape and music | T17–T23 | R20, R43, R52 |
| T25 | Accessibility, settings, and UI hardening | T15, T22–T24 | R08, R42, R44–R47 |
| T26 | Cross-system correctness and branch regression | T14–T25 | R01, R04, R28, R34, R37–R40, R49 |
| T27 | Profiling, soak, and optimization | T23–T26 | R48 |
| T28 | End-to-end acceptance and host release | T26, T27 | R01–R52 final verification |

## Phase A — A working foundation

### T01 — Establish the project and reproducible environment

- [ ] **Implement and verify T01.**

**Read:** D00, D10, D12; R02, R03, R51. **Depends:** none.

**Own:** repository root setup, `project.godot`, `.godot-version`, `.gitignore`, `README.md`, `specs/`, `docs/` execution records, minimal boot/main-menu scenes.

Inspect existing files and preserve unrelated work. Select/freeze a compatible installed stable Godot 4 version, record how to execute it, and ensure export-template compatibility is discoverable. Set Compatibility rendering, 60 Hz physics, default input actions, named collision layers, and the three-document spec location. Create the exact intended directory layout and progress/traceability templates. Main scene opens a minimal honest title shell; unavailable future actions may be disabled only during this foundation stage.

**Verify:** fresh headless import/parse; visible launch if available; exact engine version recorded. README launch command matches actual environment. No required dependency outside the pinned engine.

**Handoff:** engine path/version, environment capabilities and unavailable verification tools, project entrypoint, repository checkpoint, execution-record paths. Do not spend money or change system security settings to install tools.

### T02 — Freeze types, content registries, and service boundaries

- [ ] **Implement and verify T02.**

**Read:** D03–D07, D10–D11; R04, R23, R49. **Depends:** T01.

**Own:** `core/`, service skeleton contracts in `autoload/`, resource classes and content schemas under `data/`, `tools/validate_content.gd`, `tests/run_all.gd`, contract documentation.

Implement the shared types, ActionResult codes, transaction coordinator, stable ID registries, service access pattern, and EventBus signals. Populate authoritative item and enemy definitions with the design values; reserve all quest, dialogue, landmark, scene, spawn-group, and choice IDs. Define collision masks and mode enums once. Pick resource/JSON representation per registry. Build a validator that fails on invalid content and a runner that can execute focused suites with isolated save directories. Skeleton services must clearly report unsupported operations until their owning tasks implement them; no false-success returns.

**Verify:** duplicate/broken-ID fixtures fail, valid item/enemy registries pass, all 23 item IDs resolve, event subscription teardown is testable, and failed staged transactions cannot mutate state.

**Handoff:** public type/API definitions, canonical registries, error codes, collision/mode table, test command and fixture conventions. Later agents consume these contracts without inventing replacements.

### T03 — Create the original low-poly visual toolkit

- [ ] **Implement and verify T03.**

**Read:** D08, D10; R41, R52. **Depends:** T02.

**Own:** visual assets, materials, original texture/icon generation, reusable modular art scenes, `tools/generate_assets.gd`, `docs/asset_manifest.md`.

Produce a reusable baseline for all required environment/actor/gear families. Make assembled knights recognizable through articulated limbs, armor, helmets, weapons, and shields. Establish palette, material roughness, texture scale, world dimensions, and reusable animation rig/part names. Generate needed original icons and small texture atlases locally. Add a showcase scene containing representative exterior, interior, and actor assets at correct scale. External packs are optional; absence of downloads must not block completion.

**Verify:** generation is repeatable; regenerated assets keep stable paths; no missing material/icon references; inspect showcase from first-person distance and at retro resolution. Record provenance for every output family.

**Handoff:** asset catalog and paths, part/animation naming contract, generation procedure, screenshots or explicitly unverified visual status. T23 owns later polish; this task still delivers usable recognizable art.

### T04 — Implement the first-person player

- [ ] **Implement and verify T04.**

**Read:** D03, D08–D10; R07, R08. **Depends:** T02, T03.

**Own:** `scenes/player/`, `scripts/player/`, movement/input tests, simple movement test arena.

Implement grounded movement, normalized diagonal input, sprint, jump, stamina requests, captured mouse look, pitch clamp, and the visible gear mount. Read equipment/camera settings through contracts rather than hardcoded UI references. Add simple stairs/slopes/walls to the test arena. Centralize input-action queries so remapping can be added without changing every mechanic. Ensure frame-rate-independent physics and adjustable sensitivity/invert-Y/FOV.

**Verify:** displacement tests, grounded-only jump, zero-stamina sprint fallback, wall collision, pitch clamp, and visible mouse behavior. Do not label movement “finished” from a static camera screenshot.

**Handoff:** player scene entrypoint, spawn/reset API, camera and hand mount transforms, movement tests, supported settings hooks.

### T05 — Implement interaction and modal control

- [ ] **Implement and verify T05.**

**Read:** D03, D09–D10; R09, R45. **Depends:** T04.

**Own:** interaction components, GameModeController, input ownership, modal host, test interactables.

Implement occluded focus ray, InteractionOffer, one-press activation, and commit-time validation. Create the mode controller for all specified modes and subordinate confirmations, including pause/cursor/focus policy. Add reusable door, readable, container, and NPC interaction adapters that call their future domain services. Test adapters may use explicit fixtures; game-facing UI must not fake completed actions.

**Verify:** through-wall rejection, closest target, held-E deduplication, nested modal close, alt-tab pause, held-attack release behavior, and movement freeze/resume.

**Handoff:** adapter base classes, exact mode transitions, fixture scene, input-release policy. Combat and UI agents must use this controller.

### T06 — Implement player melee and the authoritative damage resolver

- [ ] **Implement and verify T06.**

**Read:** D04–D05, D10; R12–R16, R20. **Depends:** T02, T04, T05.

**Own:** combat math/component scripts, first-person attack/guard presentation, damage-query helper, combat unit/integration fixtures.

Implement light/heavy phase machines, stamina commitment, one queued follow-up, swept spatial hit checking, single-victim and per-sequence deduplication, armor, front-cone blocking, parry window/cooldown, guard break, damage immunity, and single death dispatch. Domain state owns timing; animation reflects it. Add a damageable dummy and a scripted attacking fixture to exercise defense before AI exists. Keep AudioService events addressable even before final sounds arrive.

**Verify:** concrete numerical block/damage cases; boundary timing tests; wall occlusion; two victims; repeated contact; insufficient stamina; pause in every attack phase; simultaneous lethal damage. Exercise real mouse/keyboard combat in the arena if available.

**Handoff:** combat API implementation, timing diagrams or tables, event IDs, test results, animation hooks. Do not duplicate damage formulas inside enemy/UI scripts.

### T07 — Implement ordinary enemies and navigation

- [ ] **Implement and verify T07.**

**Read:** D04, D10; R18–R20. **Depends:** T03, T06.

**Own:** ordinary actor scenes, AI scripts, navigation arena, perception/encounter coordination, enemy tests.

Implement four archetypes using shared combat. Add the full state machine, sight/noise/proximity occlusion, leash/return, stagger/death, navigation synchronization, bounded replanning, stuck recovery, and two-attacker reservations. Provide ordinary deserter guarding without player-only parries. Dead actors expose a persistent loot interface to be fulfilled by T08. Actor identity is a stable entity ID supplied by its spawn manifest.

**Verify:** wall concealment, chase around an obstacle, loss of sight, return health reset, reservation release, visible no-teleport behavior, death once, and each archetype's attack readability.

**Handoff:** reusable enemy scene/factory, navigation requirements, group-spawn API, loot hook, tuning observations. Boss-specific behavior remains T20.

### T08 — Implement inventory, equipment, and persistent loot

- [ ] **Implement and verify T08.**

**Read:** D05, D10–D11; R23–R25, R27. **Depends:** T02, T05, T06.

**Own:** inventory domain services, stack/equipment state, loot containers/corpses, equipment presentation bindings, inventory tests.

Implement normal/key inventory separation, stack limits, equipped ownership, start loadout, capacity previews, incremental loot collection, and pending reward delivery. Bind equipped weapons/shields/armor to actual combat and first-person visuals. Provide semantic container IDs and deterministic loot; record remaining contents in WorldStateService, not only scene nodes. Ensure the last melee weapon cannot be sold and equipment cannot change during committed actions.

**Verify:** full/partial capacity, multiple stacks, invalid equipment, duplicate pickup requests, one starting grant, reload-ready snapshots, pending reward claim once, and enemy gold only once.

**Handoff:** inventory/equipment APIs, persistent loot representation, reward delivery calls, UI-friendly view models and tests.

### T09 — Implement economy, consumables, resting, and death recovery

- [ ] **Implement and verify T09.**

**Read:** D04–D05, D11; R17, R22, R26, R27. **Depends:** T07, T08.

**Own:** economy/consumable/rest/death services, shop content, resource transactions, related tests.

Implement finite equipment stock, unlimited consumable availability, pricing formulas, atomic buy/sell, timed consumables, damage-first cancellation, stamina regeneration, rest eligibility, inn fee policy, death penalty, and living-encounter reset. Use supplied rest-anchor IDs and a temporary test-arena anchor until world travel exists. Finish retry/idempotence semantics through the shared transaction coordinator.

**Verify:** insufficient funds/capacity with zero mutation; no price arbitrage across all ending multipliers; duplicate committed purchase; heal-at-full rejection; interruption at completion tick; exact death penalties; unsafe rest refusal; no repeated death charge.

**Handoff:** service APIs and snapshot fields, shop definitions, danger predicate, respawn request contract for WorldRouter, tests.

## Phase B — A connected, persistent game

### T10 — Build the authored exterior and its route manifest

- [ ] **Implement and verify T10.**

**Read:** D02, D08, D10; R05, R10, R11. **Depends:** T03, T05, T07.

**Own:** exterior geometry, map/landmark manifest, `tools/bake_world.gd`, exterior navigation, discovery and safe-anchor placement.

Create the valley, recognizable landmark blockouts using usable art, central road, two bypass loops, boundary terrain, water hazards, and reserved objective/encounter areas. Establish the start position, village shrine, and authored spawn/entrance transforms. Use deterministic decorative placement with reserved corridors. Build and commit navigation data or a deterministic bounded bake step, without per-frame rebaking. Supply map coordinates usable by UI.

**Verify:** physically walk every connecting route; validate all nine landmark IDs and entrance anchors; no starting overlap; both checkpoint bypasses pass; discovery fires once; deterministic regeneration preserves IDs and placements.

**Handoff:** map manifest, route walkthrough, entrance/rest IDs, nav generation procedure, objective placement reservations. T17 completes encounter/story dressing.

### T11 — Implement interiors, world routing, and hazard recovery

- [ ] **Implement and verify T11.**

**Read:** D02, D04, D10–D11; R06, R11. **Depends:** T09, T10.

**Own:** WorldRouter, inn/crypt/undercroft scene shells, paired doors, safe spawns, recovery triggers/tests.

Build the three interior layouts with real collision/navigation, stable entry/exit registries, and persistent scene-state application. Implement fades, input lock, nav synchronization, and player persistence. Add the undercroft story gate and contextual rejection message. Connect rest/death requests to the proper scene/anchor. Add deep-water/out-of-bounds recovery and emergency village fallback.

**Verify:** ten round trips per interior, invalid/missing entrance handling, safe-return transforms, repeated death travel, no duplicate player, and water/fall recovery. Run an explicit case leaving a scene while an enemy still has a player reference.

**Handoff:** scene/entrance registry, travel/recovery APIs, ordering guarantees, screenshots/walkthrough if possible.

### T12 — Implement quest state, predicates, and all definitions

- [ ] **Implement and verify T12.**

**Read:** D05–D07, D10–D11; R28, R33, R34. **Depends:** T02, T08, T09.

**Own:** QuestService, predicate/effect whitelist, all twelve quest definitions, reward transactions, quest fixtures.

Encode prerequisites, objective IDs, data targets, reward values, item consumption, evidence retention, Wren/medicine/ending enums, and quest states for the entire campaign. Implement reconciliation on activation/load and idempotent cross-domain completion including pending deliveries. Physical objectives are connected in later tasks; this task must already define their IDs so world and dialogue agents cannot invent competing ones.

**Verify:** early collection, duplicate events, unsatisfied prerequisites, three distinct candle entities, full-inventory rewards, failed transaction rollback, permanent acquisition flags, and all main/side state graphs with domain fixtures.

**Handoff:** objective registry, complete quest data, condition/effect operations, content-validator additions, tests and downstream world-target list.

### T13 — Implement dialogue and the canonical cast

- [ ] **Implement and verify T13.**

**Read:** D06–D07, D09–D10; R32, R34. **Depends:** T05, T12.

**Own:** DialogueService, dialogue resources/localized English strings, NPC interaction adapters, dialogue UI fixture.

Create the eight speakers and their required lines, quest offers/turn-ins, shop/rest access, contextual greetings, and named choice IDs. Implement condition reevaluation, safe Leave behavior, transaction-driven effects, and dynamic option priority. The UI presents choices but cannot mutate domain state. Use static actor fixtures; exterior placement is T17, and detailed story encounters are verified in their owning content tasks.

**Verify:** dialogue-graph validation, unavailable/stale choice rejection, quest turn-in priority, shop/rest accessibility, all Leave paths, and explicit Rusk challenge behavior without premature combat.

**Handoff:** speaker/node/choice IDs, strings, dialogue conditions, verified fixture paths, placement dependencies.

### T14 — Implement durable saves, settings, and session lifecycle

- [ ] **Implement and verify T14.**

**Read:** D09–D11; R37–R40. **Depends:** T09, T11, T12, T13.

**Own:** SaveService, save codecs/checksum/validation, slot metadata, settings persistence, GameSession lifecycle, save-failure fixtures.

Serialize every specified domain field into a versioned envelope. Implement detached validation, staged write/readback/backup/replacement, primary/backup recovery, safe save queuing, valid-slot selection, new-game reset, and clean title/session teardown. Record successful committed transaction receipts so reloading cannot duplicate rewards. Keep settings independent of game slots. Do not persist partial enemy HP or live node identity.

**Verify:** full snapshot round-trip; corrupt/unknown-schema/invalid-ID fixtures; failures at every write stage; safe gameplay after failed load; duplicate rewards after reload; inventory/quest/world reset on New Game; no overwriting manual slots through autosave.

**Handoff:** exact schema, write recovery policy, save paths, isolated test paths, supported UI slot metadata, extensive failure-test results.

### T15 — Build functional HUD, menus, journal, map, and onboarding

- [ ] **Implement and verify T15.**

**Read:** D02–D03, D05, D07, D09; R10, R44–R47. **Depends:** T10, T13, T14.

**Own:** UI scenes/scripts, title/pause/settings/save/load, HUD, inventory/equipment/shops, journal/readables, map, onboarding prompts.

Connect real domain APIs to usable controls. Implement slot metadata, pending rewards, tracked quests, indoor entrance hints, item/stat comparisons, and clear rejection messages. Supply actual settings controls for remapping, mouse/FOV, text scale, audio, and rendering hooks; final stress/polish is T25. Add concise contextual hints and a nonrewarding training dummy. No UI command should be a fake success toast.

**Verify:** keyboard/mouse paths through every implemented operation, data refresh after mutation/load, modal pause/cursor policy, honest locked/empty states, and basic 1280×720 layout. Record which late-game screens require later content to inspect.

**Handoff:** UI navigation map, screenshots if available, settings hooks consumed by later art/audio work, known layout issues with owners.

### T16 — Integrate and prove Bread and Iron

- [ ] **Implement and verify T16.**

**Read:** D02–D07, D11–D12; R01, R29, R47, R50. **Depends:** T06, T07, T08, T09, T10, T11, T12, T13, T14, T15.

**Own:** opening spawn, Mara/Oswin village placement, cart encounter/container, MQ01 wiring, slice integration fixtures; bounded repairs in predecessor modules.

Make the complete opening loop playable: start, learn, speak to Mara, travel, fight/bypass two cutpurses, loot medicine, return, collect one reward, unlock MQ02, use shop/equipment, rest, save, quit, reload. Use the actual final-pattern services and scenes, not a separate throwaway demo implementation. Preserve these placements when T17 fills the valley.

**Verify:** acceptance S01 plus a death, full-inventory turn-in, early coffer pickup, and reload after completion. Play without debug grants/teleports when the environment allows. Resolve integration failures before proceeding to mass content wiring.

**Handoff:** playable milestone checkpoint, route instructions, evidence, fixed interface issues, measured opening pacing, and remaining gates. Continue immediately to T17 after verification; the user requested the full game.

## Phase C — The complete campaign

### T17 — Populate the valley and all fixed world content

- [ ] **Implement and verify T17.**

**Read:** D02, D06, D08, D10; R05, R10, R18, R32, R41. **Depends:** T10, T11, T16.

**Own:** exterior landmark dressing, named NPC stations, spawn/loot/object manifests, environmental readables, discovery/rest points, world-content validation.

Complete all nine landmarks, every exterior encounter group, the neutral camp/courtyard distinction, and physical targets reserved by T12. Preserve MQ01's tested route. Instantiate the remaining named NPC stations, exterior side-quest objects, signs, readable evidence, containers, rest points, and clear route cues. Interior encounter/quest objects are finished by T18/T20. All entities receive stable IDs and apply saved state on construction. Ensure story sources remain available independently of enemy corpse loot.

**Verify:** manifest completeness and counts across assigned scenes; walk all exterior routes; interact with each NPC and exterior objective; inspect doorways, collision, nav gaps, and boundary recovery. Flag intentional interior assignments instead of silently leaving targets missing.

**Handoff:** full world-target registry, enemy/container ID list, remaining interior targets with assigned task, map screenshots and route findings.

### T18 — Implement the toll investigation and monastery arc

- [ ] **Implement and verify T18.**

**Read:** D02, D06–D07; R29, R31, R33. **Depends:** T12, T13, T14, T15, T16, T17.

**Own:** MQ02/MQ03 scene wiring, checkpoint evidence, Elian dialogue integration, crypt encounters/chimes/vault, related fixtures.

Finish notice/receipt interaction and Mara's MQ02 handoff. Populate crypt chambers with the four keepers and readable puzzle. Implement reed→stone→flame chimes, reset feedback, durable solved door, charter pickup, and Elian's attestation. Make all clues available in text and ensure early crypt exploration works. The outdoor two keepers and indoor four keepers use distinct IDs.

**Verify:** play from MQ01 completion through MQ03; take a bypass route; solve/reset puzzle; reload during partial progress and after solving; collect charter before MQ03 and reconcile; muted-audio solution. No money or mandatory checkpoint kill can gate progress.

**Handoff:** pre/post-MQ03 saves or reproducible fixtures, clue copy, puzzle state tests, main-route evidence.

### T19 — Implement Wren, the watchtower, and the ledger choice

- [ ] **Implement and verify T19.**

**Read:** D02, D06–D07; R29, R32–R34. **Depends:** T17, T18.

**Own:** MQ04 world/dialogue wiring, camp interactions, watchtower ledger/locker/encounters, Wren terms choice fixtures.

Complete the Briar Camp story visit, watchtower route, three hostile raiders/cutpurse placement, ledger acquisition, Wren testimony/terms choice, and Mara report. Keep neutral camp residents separate from hostile raider faction instances. The badge locker is physically available for SQ05 even before its acceptance. Use the same transaction keys on repeated dialogue opens.

**Verify:** both amnesty and restitution paths; cancel before choosing; ledger collected early; reload before/after terms; report reward once; unrelated Wren options remain available. Confirm old enemy defeats and partial loot persist through the trip.

**Handoff:** both MQ04 branch fixtures, stable terms flags, MQ05-unlocked checkpoint, watchtower integration results.

### T20 — Build Rookwatch, the captain duel, and MQ05

- [ ] **Implement and verify T20.**

**Read:** D04, D06–D07, D10–D11; R21, R29, R33. **Depends:** T07, T14, T19.

**Own:** undercroft final geometry/encounters, Ada evidence handoff, boss actor/controller, arena gate, seal chest, MQ05 reward integration.

Implement Ada's explicit charter/ledger check, storehouse access, undercroft retainers, Rusk dialogue/challenge, two attack patterns/phases, breath opening, gated fight, durable victory, and fixed seal chest. Complete Ada's return dialogue and Watchblade pending-delivery support. The boss extends the shared combat system; it must not create a second damage math implementation.

**Verify:** normal victory; leave before challenge; death and recovery; loading during a live encounter; parry both patterns; phase transition once; leave/reload after victory before seal collection; full-inventory Watchblade reward; MQ06 unlocked once.

**Handoff:** boss test arena/checkpoints, phase timings, S11 results, pre-ending save, observed combat issues for T23/T27.

### T21 — Complete all six side quests and their world reactions

- [ ] **Implement and verify T21.**

**Read:** D05–D07; R25, R27, R30, R33, R34. **Depends:** T17, T19, T20.

**Own:** all side-quest scene/dialogue/effect wiring, candle/light and badge reactions, inn fee unlock, medicine recipient branch, side-quest fixtures.

Connect the kiln hammer, ferry blankets, shrine ring, three distinct candles, watchtower badge, and separate camp medicine cache. Include required giver/turn-in copy, exact currency/gear/consumable rewards, inventory overflow, and postcompletion visuals. Make Wren/Mara medicine delivery mutually exclusive without hiding either character's other quests. Side content may share locations, never consume the wrong item or commandeer a main objective.

**Verify:** each quest in normal order and with early pickups; both medicine branches; full-inventory gear rewards; duplicated candle activation; repeat turn-in; inn cost before/after; save/load visual reactions. Verify side quests can still be accepted from a simulated completed-campaign state, then repeat with real ending states in T22.

**Handoff:** six completion fixtures, branch fixtures, reward audit, world-reaction evidence and edge-case results.

### T22 — Implement The Last Toll and all persistent endings

- [ ] **Implement and verify T22.**

**Read:** D05, D07, D09, D11; R26, R29, R35, R36. **Depends:** T14, T20, T21.

**Own:** MQ06 Mara/writ-table sequence, ending transaction, aftermath adapters, epilogue UI/content, branch/reload tests.

Present all three outcomes and explicit confirmation. Commit ending, quest completion, shop modifier, banners/signs, and checkpoint reactions atomically. Update loaded actors immediately and unloaded actors when instantiated. Preserve dead guards and disable the correct survivors for free_road. Save before epilogue with honest retry/continue-unsaved failure flow. Render all three panels using Wren and medicine flags. Add return-to-valley, title, and journal replay paths.

**Verify:** all ending branches, cancel, repeated confirm, failed save/retry, reload without epilogue loop, correct price changes, already-dead checkpoint soldiers, side quests after each ending, and replay after completing SQ06 later.

**Handoff:** three post-ending checkpoints, branch matrix, S08 evidence, fully completable content status. No final branch may be represented only by different text with unchanged promised world behavior.

## Phase D — Cohesion, evidence, and delivery

### T23 — Finish art, animation, lighting, and rendering

- [ ] **Implement and verify T23.**

**Read:** D04, D08–D09; R20, R41, R42. **Depends:** T03, T17, T18, T19, T20, T21, T22.

**Own:** final visual assets, actor/weapon animation tuning, scene lighting/dressing, Retro/Native viewport implementation, graphics settings integration; gameplay contracts remain fixed.

Bring every required asset family to the agreed visual standard. Remove development capsules/grayboxes from player-facing routes, improve silhouettes and material consistency, align animations with authoritative attack phases, and make crypt/boss telegraphs readable. Finish aspect-correct 540p rendering with independent native-resolution UI, shadows/fog options, and camera comfort settings. Keep all effects compatible with the chosen renderer. Do not move required collision/objective anchors casually during dressing.

**Verify:** inspect the eight required release views; walk collision after art changes; compare Retro/Native at 4:3, 16:9, and 21:9; verify targeting alignment and first-person gear for all equipment tiers. Visual improvements cannot regress reach, interaction, or quest pickup access.

**Handoff:** captured views/settings, asset provenance updates, animation timing evidence, any measured performance issues for T27.

### T24 — Complete audio and musical atmosphere

- [ ] **Implement and verify T24.**

**Read:** D08; R20, R43, R52. **Depends:** T17, T18, T19, T20, T21, T22, T23.

**Own:** audio assets/generation, AudioService, buses, zone ambience/music, event mapping, audio provenance.

Produce or source-with-license every required cue and original musical/drone bed. Connect footstep surfaces, melee outcomes, inventory/UI, puzzle, bell, doors, and quest events. Implement zone transition/crossfade, pause behavior, independent bus levels, and cleanup on scene/title changes. Restrained procedural audio is acceptable; silent event handlers and missing files are not. Avoid clipping, harsh continuous high tones, and excessively loud UI compared with combat.

**Verify:** listen to all cues, inspect bus/mute controls, traverse exterior/interiors repeatedly, pause/resume, and return to title without stacked loops. Confirm matching visual signals with all buses muted.

**Handoff:** audio-event inventory, listening evidence, mix settings, generation/source licenses, unresolved audio defects if any.

### T25 — Harden controls, accessibility, and presentation flows

- [ ] **Implement and verify T25.**

**Read:** D03, D08–D09; R08, R42, R44–R47. **Depends:** T15, T22, T23, T24.

**Own:** accessibility/settings polish, UI layout/focus, prompt clarity, input-remapping integration, modal regression cases.

Complete text scaling, remapping/swap flows, invert-Y/sensitivity/FOV, no-bob/no-shake, audio controls, window modes, keyboard focus, and responsive scrolling. Audit every narrative/quest/ending line in the real panels. Remove inaccessible disabled final-release buttons and debug wording. Ensure save/reward/transaction failures display actionable messages. Settings must persist independently across a New Game.

**Verify:** S09 and S12; every menu with keyboard only; rebind all gameplay actions; close nested panels; alt-tab during attack/heal; scale to 150% at 720p; switch Retro/Native in/out of modals; review onboarding from a fresh settings profile.

**Handoff:** accessibility/input checklist, screenshots at maximum text scale, resolved UI defects, tested settings round-trip.

### T26 — Audit state integrity and cross-system regression

- [ ] **Implement and verify T26.**

**Read:** all requirements, especially R04, R28, R34, R37–R40, R49; D10–D12. **Depends:** T14, T15, T16, T17, T18, T19, T20, T21, T22, T23, T24, T25.

**Own:** integration/branch/failure tests, validator completeness, traceability audit; targeted fixes with the affected module owner/lead.

Run content/scene validation and all consequential domain tests. Exercise S02–S08 and S11, plus normal lifecycle, duplicate callbacks, scene reload, early evidence, pending deliveries, and independent save slots. Audit that the actual content count and IDs match the spec. Include dialogue/world-state integration so APIs that pass in isolation do not hide missing physical targets. Investigate any mismatch; fix and rerun the narrow affected tests, then required release suite.

**Verify:** no missing mandatory content; all automated/integration assertions pass; every R ID has an implementation owner and evidence plan; save failures retain a recoverable state; all branch fixtures are reproducible. Do not use direct field injection as the sole proof of UI-driven transitions.

**Handoff:** machine-readable or concise test report, traceability status for all 52 requirements, defect resolutions, exact remaining visual/export gates.

### T27 — Profile, soak, and optimize the real game

- [ ] **Implement and verify T27.**

**Read:** D10, D12; R48. **Depends:** T23, T24, T25, T26.

**Own:** profiling harness/route, performance report, targeted culling/AI/resource/nav optimizations; preserve game behavior and asset IDs.

Measure the actual release-equivalent game, after warmup, in village, forest combat, crypt, and boss. Record hardware, engine, renderer, window/internal resolution, settings, sample duration, median and 95th-percentile frame time, scene-load time, and memory behavior. Use at least 120 seconds of sampling per representative route segment when practical. Run the 20-minute mixed soak. Prioritize repeated resource loads, navigation cost, inactive AI, excess lights, and leaking listeners over speculative rewrites.

**Verify:** R48 targets or explicitly recorded failures, bounded active AI/work, no repeated errors, no growth in duplicated actors/loops/listeners across transitions. Rerun the relevant scene/state tests after optimization. If graphics profiling is unavailable, preserve the harness and mark the gate unverified.

**Handoff:** measured report, concrete optimization diffs, before/after evidence, remaining hardware limitations. Never invent M1 or other platform results from an unrelated test host.

### T28 — Perform end-to-end acceptance and package the release

- [ ] **Implement and verify T28.**

**Read:** all three specs, R01–R52, S01–S12. **Depends:** T26, T27.

**Own:** final end-to-end verification, export presets/builds, README/credits/license completion, release report, bounded defect repair.

Run an actual new-game-to-ending playthrough with normal controls and no debug grants/teleports, complete all six side quests, and verify the other two endings from valid checkpoints. Capture required visual evidence and confirm all gates. Import from a clean checkout/location. Export the host platform with matching templates, launch independently of the editor, test offline gameplay and save/load, and retain Windows/macOS/Linux preset definitions with accurate verification status. Audit shipped asset licenses and remove development-only entrypoints from ordinary menus.

**Verify:** every requirement has PASS evidence; all twelve acceptance scenarios have a result; no severe blocker, missing feature, or invented test remains. If a mandatory gate is blocked, deliver the runnable implementation and a named list of unverified/failed gates rather than claim a finished game. Keep optional platform builds clearly distinguished from the required host build.

**Handoff:** source location, host artifact location, pinned engine, launch/test/build instructions, tested platforms/settings, requirement report, actual run evidence, license manifest, known issues, and next action for any blocked gate. Do not publish or submit to a store.

## Requirement-to-task coverage map

T28 verifies all requirements; this map identifies the primary implementation owners and focused checks before release.

| Requirements | Implementation / focused verification tasks |
|---|---|
| R01 | T16, T17–T22, T26, T28 |
| R02–R03 | T01, T02, T28 |
| R04 | T02, T12–T14, T26 |
| R05 | T10, T17 |
| R06 | T11 |
| R07 | T04 |
| R08 | T04, T05, T15, T25 |
| R09 | T05 |
| R10 | T10, T15, T17 |
| R11 | T10, T11, T20 |
| R12–R16 | T06, T07, T20 |
| R17 | T09 |
| R18–R19 | T07, T17, T18, T20 |
| R20 | T06, T07, T23, T24 |
| R21 | T20 |
| R22 | T09, T11, T14 |
| R23 | T02, T08 |
| R24–R25 | T08, T12, T21 |
| R26 | T09, T22 |
| R27 | T08, T09, T21 |
| R28 | T12, T26 |
| R29 | T16, T18, T19, T20, T22 |
| R30 | T21 |
| R31 | T18 |
| R32 | T13, T17, T19 |
| R33 | T12, T18–T21, T26 |
| R34 | T12, T13, T19, T21, T22, T26 |
| R35–R36 | T22 |
| R37–R40 | T14, T22, T26 |
| R41 | T03, T17, T23 |
| R42 | T23, T25 |
| R43 | T24 |
| R44–R47 | T15, T25 |
| R48 | T27 |
| R49 | T02, system-owning tasks, T26 |
| R50 | T16, T28 |
| R51 | T01, T28 |
| R52 | T03, T24, T28 |

## Handoff template for each finished task

Write `docs/handoffs/Txx.md` with the following fields:

```markdown
# Txx — Task title
Status: IMPLEMENTED / VERIFIED / BLOCKED
Repository checkpoint: <commit or precise working-tree reference>

## Behavior delivered
<Observable functions now available; requirement IDs.>

## Changed files and contracts
<Paths; public signatures; data IDs; approved contract changes.>

## Verification actually performed
<Exact commands/inputs, result, evidence path, environment.>

## Remaining gaps
<Failed/unrun criteria and why; no disguised TODO features.>

## Successor instructions
<How to instantiate/use the work; fixtures and integration caveats.>
```

## Definition of a successful one-shot handoff

The initial three-document package gives the implementation lead enough product and technical decisions to work without repeated design clarification. It does not remove the need for execution feedback. A successful build ends with a playable valley, twelve completed quest implementations, all ending branches and aftermath, reliable saves, deliberate art/audio, and evidence for the mandatory requirements. The lead should expect to diagnose and correct mistakes inside this task sequence until that outcome is real.
