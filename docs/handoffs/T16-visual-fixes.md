# T16 opening visual fixes

Status: VERIFIED for the bounded paint/support corrections. Root owns commit, push and normal-control opening acceptance.
Baseline: clean `5d94f94` before this patch.

## Changes

- Medicine chest body and lid use one matte `medicine_blue` material (`#496F94`), matching Mara's blue-box clue. Iron bindings, latch, parchment panel, red medical symbol, geometry and lid pivot remain unchanged. Other chest families remain wood.
- The existing deterministic generator calculates palette-atlas rows from the named palette size so all 21 colors appear. Regeneration changes only `assets/models/props/medicine_chest.tscn`, `assets/textures/palette.png`, and new `assets/materials/medicine_blue.tres`; all 157 other prior asset files are byte-identical. Two consecutive generation runs produced identical bytes across all 160 asset files.
- Each rest lantern sits on a 0.4 × 0.5 × 0.4 m wooden support with matching world collision. Lamp height, interaction position, canonical rest anchors, persistent IDs and entity counts remain unchanged. The support is excluded from its own Rest visibility ray.
- The asset manifest records the new paint and runtime interaction geometry. No external assets or new generation system were introduced.

## Verification performed

Pinned Godot `4.5.2.stable.official.6ce3de25a`:

- `--headless --path . --script res://tools/generate_assets.gd`, twice: exit 0; scoped and repeatable output verified by SHA-256 comparison.
- `--headless --path . --editor --import --quit`: exit 0, no parse/import errors.
- `--headless --path . --script res://tests/run_all.gd -- --suite=unit/test_art.gd`: **749 assertions passed**, zero failed suites.
- `--headless --path . --script res://tests/run_all.gd -- --suite=integration/test_world_travel.gd`: **628 assertions passed**, zero failed suites. Sixteen added checks cover all three exterior rest points and the inn: support presence, unchanged safe-anchor capsule clearance, ray contact matching the visible support top, and actual InteractionRay Rest focus/availability.
- Actual integrated-world before/after GPU frames inspected at 1280×720 UI / 960×540 Retro view. The coffer is recognizably blue; the inn lantern is visibly supported. Both retain their correct interaction prompts. Log: `/tmp/mireward-opening-visual-after.log`, ending `OPENING_VISUAL_COMPLETE` without errors or warnings.

Images are in ignored `tests/output/opening_visual/`: `before_medicine_coffer.png`, `after_medicine_coffer.png`, `before_inn_rest_approach.png`, and `after_inn_rest_approach.png`. The fixture uses an isolated save directory, scripted viewpoints, a paused simulation and forced offscreen draws. It does not provide S01 playthrough evidence. No input was sent to the separately running exported game.
