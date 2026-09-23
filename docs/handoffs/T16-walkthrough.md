# T16: Normal-physics opening walkthrough

Status: VERIFIED automated normal-physics opening traversal after root fixed the held-key persistence defect. Native hardware-input acceptance remains UNVERIFIED.

## Scope and mechanism

`tests/integration/test_opening_walkthrough.gd` instantiates the production GameRoot and starts New Game using the actual focused title button and Enter events. Its steering helper reads the navigation path and player position, then sends press/release events for the current InputMap movement binding. It never writes player position, velocity, quest state, currency, inventory or world records, never grants items, never calls spawn_at, and never changes time_scale or physics tick rate.

The default branch performs a short ten-meter normal walk crossing the real movement-hint persistence event and checks clean teardown. The longer route is opt-in with `MIREWARD_OPENING_WALKTHROUGH=1`. Root's runner timeout is 360 seconds only for that exact suite with that opt-in value; other suites retain 120 seconds.

In headless mode, Godot cannot capture a cursor. The fixture therefore calls the production Player.apply_look method with calculated sensitivity-scaled mouse deltas. In a captured graphical run it injects mouse motion into the root viewport, through the normal GameRoot/SubViewport/player input path. Both mechanisms are counted in the report. Neither establishes native hardware mouse/keyboard play.

Interaction uses the live eye ray and ordinary E binding. Menu actions focus a real visible button and send Enter press/release events. There are no direct quest/inventory/recovery mutations. The full route is authored-start to Mara, southern approach to the medicine coffer behind the north-facing cutpurses, return to Mara, inn doorway, Tamsin purchase and paid rest, and manual save/load through the UI. Walking remains 4 m/s with normal acceleration; no sprint or time acceleration is used. The bypass is an allowed opening path, not a disabled-enemy fixture.

## Required results

- Actual New Game starts at the manifest position.
- Continuous movement crosses each navigation leg without a position jump.
- Real Mara dialogue accepts MQ01; real coffer interaction and Take button acquire medicine.
- Returning normally completes MQ01 once, grants exactly 18 crowns and one bandage, retains acquisition evidence, and makes MQ02 available.
- A real validated autosave contains the completed opening.
- Tamsin sells one bread for 5 crowns and the real inn rest charges 4 once and reaches its anchor.
- A manual save/load preserves earned progress, currency and occupied inn reconstruction.

The test writes ignored per-leg timing/distance/health and summary evidence to `tests/output/opening_walkthrough/report.json` only for the full opt-in run. The runner isolates and removes test save slots; real user save files are not used. Normal walks and their report are integration evidence, not an unassisted native campaign or release acceptance claim.

## Reproduction

```sh
GODOT="$HOME/.local/share/mireward-tools/godot-4.5.2/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --script res://tests/run_all.gd -- --suite=integration/test_opening_walkthrough.gd
MIREWARD_OPENING_WALKTHROUGH=1 "$GODOT" --headless --path . --script res://tests/run_all.gd -- --suite=integration/test_opening_walkthrough.gd
```

## First-run finding

The initial full run stopped after 6.86 m while still holding W. Diagnostics showed `Input.is_physical_key_pressed(KEY_W)=true`, `Input.is_action_pressed(move_forward)=false`, gameplay unpaused and player input enabled, with only a floor collision. At that moment the movement hint had just persisted its dismissal. SaveService.save_settings reapplied every InputMap binding even though bindings were unchanged, erasing the held action state. The test deliberately does not hide this by tapping movement repeatedly. Root was sent the exact reproduction and owns the production input-state fix.

Root fixed SettingsValidation.apply_bindings to leave matching events intact, replacing only changed bindings. The walkthrough reran without movement taps or another input workaround.

## Verification actually performed

Pinned Godot 4.5.2, headless production scene and normal physics:

- Default ten-meter smoke: **PASS 8 assertions**, zero failed suites. It crosses actual hint persistence while holding the movement key, releases normally and leaves MQ01 unaccepted.
- Full opt-in opening: **PASS 50 assertions**, zero failed suites. The route covered **438.71 m in 116.069 seconds**, at 60 Hz and time_scale 1. Largest observed movement step was 0.0691 m. Health stayed 100 throughout, with both cutpurses safely bypassed and undefeated.
- Actual E/ray interactions and focused UI Enter events accepted MQ01, opened/took the fixed medicine, returned to Mara, completed once for 18 crowns/one bandage, made MQ02 available, and produced a validated autosave.
- The same run walked through the inn door to Tamsin, bought bread for 5 crowns, rested for 4 crowns through actual recovery arrival, wrote a manual slot and loaded it through the real UI. Final state: MQ01 COMPLETED, MQ02 AVAILABLE, 21 crowns, 100 health, occupied inn reconstructed.

The headless run used 6640 calls to the normal Player.apply_look input calculation and zero captured mouse events. It did not use native hardware input, debug movement, direct domain mutation or combat invulnerability. The production game itself handled all state changes, including scene travel and rest/load positioning.

Evidence: `tests/output/opening_walkthrough/report.json` retains each leg's distance/time/health and the final summary. Logs: `/tmp/mireward-walkthrough-smoke.log` and `/tmp/mireward-walkthrough-full.log`. This is an automated steering-assisted integration result; it does not close unassisted/native P gates.

Optional `MIREWARD_OPENING_CAPTURE=1` saves root-viewport PNGs at authored start, Mara offer, coffer approach, turn-in and loaded inn when the same suite runs with a graphical renderer. Those captures were not executed in the reported headless pass. The capture helper does not manipulate operating-system focus or send external OS input. Root may use it for later optical review while keeping native acceptance separate.
