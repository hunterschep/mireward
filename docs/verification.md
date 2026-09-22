# Verification evidence

Starting tracked repository: specification-only commit 102f6f9. Useful unfinished foundation files were preserved and completed.

## Executed checks

| Check | Result | Evidence |
|---|---|---|
| Pinned editor and matching export templates | PASS | handoffs/T01-environment.md; official archive checksums and external smoke logs |
| Godot 4.5.2 foundation fresh import | PASS | `--headless --path . --import`, exit 0, no parse errors |
| Foundation registry validator | PASS | 23 items, five enemy definitions, 12 reserved quest IDs, eight reserved speaker IDs, nine landmarks, 26 spawns |
| Initial foundation tests | PASS | `--headless --path . --script res://tests/run_all.gd`: 11 assertions, zero failures |
| Title-shell visual and keyboard Quit | PASS | CUA screenshot inspected and Return closed the process, exit 0; handoffs/T01.md |

These checks establish only the foundation. Reserved quest/dialogue definitions are explicitly rejected by release validation. Gameplay, final art/audio, full campaign input, save recovery, soak, and game export remain unverified until their task gates execute. The separate environment probe is not the game's tested build.

## Foundation hardening and movement

- T02 audit integrated: 48 foundation assertions pass, including deliberate runner assertion/parse/runtime failures; see handoffs/T02-audit.md.
- Combat formulas/cone checks: 11 assertions pass.
- T04 real-scene headless movement: 12 assertions pass at 30/60/120 render FPS, diagonal normalization, stationary/moving sprint, air-jump refusal, wall collision, pitch and invert-Y.
- Initial mouse fixture failed because the headless display cannot establish captured mouse input. Refactored the same look calculation into apply_look for the domain check. This does not claim real mouse capture verification.
- CUA inspected the rendered movement arena with sword, shield, hands, and articulated actor art; repeated real W presses moved the viewpoint. A later mouse-look attempt lost the game window and did not establish that check. Mouse-look visual verification remains open.
- T04 strengthened sprint checks: PASS 13 assertions after checking exact sprint speed and exhausted walking speed. Rendered player capture inspected at tests/output/player/movement_arena.png; handoffs/T04.md records the remaining mouse-input gate.
- Fresh archive of foundation checkpoint 70d1530 imported and ran. Its initially absent empty tests/integration directory produced a directory warning; runner now skips absent optional suite directories. Rerun against that clean archive with the corrected runner: PASS 59 assertions, no errors.
- T03 integration review: root inspected all three 540p showcase captures and reran test_art: PASS 748 assertions. Generated architecture/props use material batching, actors retain articulated pivots, and all 80 saved model scenes load. Provenance and deterministic-generation evidence are in handoffs/T03.md and asset_manifest.md.
- T05 final focused fixture: 33 assertions passed. Root reviewed and reran the earlier 30-case version; final owner rerun adds stale action/held-E/modal teardown checks and reports full suite853 passing. Production native cursor, actual alt-tab and full-panel visuals remain open at T11/T15/T25. See handoffs/T05.md.
- T06 integrated into the actual player scene: root reran79 combat unit assertions and23 original spatial assertions; owner expanded spatial coverage to26 for rotation/protruding-wall cases. Root then ran the complete integrated suite: PASS958 assertions, zero failed suites. Transcript captured at /tmp/mireward-t06-integration.txt.
- Root launched the graphical combat arena with --capture and inspected tests/output/combat/arena.png: actor and first-person gear render in Compatibility. This is a static rendered fixture, not combat-feel or full input verification. Font provenance/bytes were independently matched to pinned Open Sans1.10 and notices included in export filters.
- T08 root staged-diff review and integration: validated container IDs and bounded saved loot, wired shared services, and tested inventory/equipment against actual player combat. Review caught merged-candle and shared-key source gaps; fixed validation and added two regression fixtures. Final focused suite: PASS130 assertions. T08 physical loot/shop/menu wiring remains later work.
- Development export built from clean tracked checkpoint257d111, with matching4.5.2 templates and valid local ad-hoc signature. Independent executable headless combat-arena smoke exited0. CUA then resumed its focus-paused arena and sent three separate native left-mouse attacks; front cutpurse fell on the third. This establishes native attack execution in the development fixture, not a campaign/release build. Artifact: builds/development/MIREWARD.app. Subsequent mouse-look attribution was unclear while the window was being used, so full look/feel checks remain open.
- T07 implementation checkpoint: owner reports63 passing real-physics enemy assertions; root staged review and import passed. This is an in-progress checkpoint: RETURN hit-history preservation and unchanged live-state refresh are under correction with new regressions. The checkpoint does not close those gates. Native AI/crowd inspection remains unverified.
- T07 final root rerun: PASS67 assertions after reviewing RETURN history, unchanged-state refresh and reservation-expiry changes. Raw spawn-facing validation added with a failing-input fixture; foundation suite now49 assertions. Native AI controls and production world/loot wiring remain separate gates.
- T09 service checkpoint: root reviewed the economy/recovery source and autoload wiring, then reran test_economy_recovery: PASS105 assertions. Includes failure/retry receipts and explicit asynchronous arrival outcomes. Same-tick healing/damage and real-player timed-use integration are still under test, so T09 remains IN PROGRESS.
- T09 final root integration:107 unit and44 real-physics assertions passed. Pending recovery now holds travel mode and blocks movement/look/interactions across panel close and failed arrival, then releases on explicit completion. Same-tick damage, paused healing and progress-preserving rest/death remain covered. Actual campaign router/UI/disk autosaves are later gates.
- T10 root integration: re-ran test_exterior with634 passing assertions; compared all pre-existing map keys, values and array ordering against b8449aa with no changes. Reviewed generator/terrain/collision/decor source and six GPU captures. Traversal evidence covers2076.1m acrossfive scripted normal-speed routes. Baseline dressing is sparse and distant landmark contrast needs the final art pass; these images do not close R41/R50. Root corrected the capture camera from60 to the actual75-degree default and850m far plane for subsequent reviews.

- T12 root integration: reviewed all quest definitions and transaction/predicate contracts, wired acquisition/defeat reconciliation, reran619 quest assertions and233 exterior-manifest assertions with zero failures. Content validator passed canonical registries. This covers domain campaigns/side choices and malformed input; physical story sources, dialogue/UI and persistent save validation remain successor gates.

- T13 integration: eight authored speakers,107 nodes and69 topics; focused suite598 assertions and release content validation passed. Root wired dialogue creation and close on new/valid restore. Staged NPCs now defer live EventBus subscriptions and interaction until activation. Speaker-qualified node IDs reject callbacks from an older speaker. Native dialogue layout and campaign placement remain T15/T17 gates.

- T11 root integration: default travel612 assertions passed; review then exposed two real rollback defects. Full menu-stack restoration and reactivation of NPC listeners after a late failed arrival now pass19 presentation and45 mode assertions in root reruns. Owner reran all612 default travel assertions on final code. Three furnished interiors and physics/navigation-backed staged world swaps are implemented; unassisted campaign traversal remains open. See handoffs/T11.md.

- Persistent runtime composition: root focused test_game_root passes27 assertions, including actual window resize at4:3/21:9/portrait/extreme-wide, Retro/Native extent, player collision and identity across travel, native modal pause, and complete player/recovery teardown. Review found/fixed the default16:9 canvas aspect policy. Root inspected GPU exterior Retro and inn Native images in tests/output/runtime. Generated mouse-event testing while capture is active reports the same yaw delta in both rendering modes; this is not a native hardware-input campaign check. Main-menu and save/UI integration remain open.
