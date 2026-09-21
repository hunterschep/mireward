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
