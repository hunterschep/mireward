# T10 exterior manifest validation

Status: VERIFIED for the focused validation suite; shared-loader integration remains with the integration owner.
Repository checkpoint: working-tree additions in the three files below; no Git mutations from this subtask.

## Behavior delivered

`ExteriorValidation.validate(map: Dictionary, containers: Dictionary, dialogues: Dictionary) -> PackedStringArray` validates the current authored exterior schema without changing its input. Empty output means these checks passed; errors identify the affected section, field, or stable ID.

- Routes require positive finite widths, at least two finite points, nondegenerate horizontal segments, and the central road plus both bypass IDs.
- Structures reuse `ExteriorLandmarks.validate` for actual art families, categories, scales, rotations, landmark links, and supported collision footprints.
- All thirteen objective reservations must match the container registry and all eight NPC reservations must match the dialogue registry. Their scene IDs, local positions, and positive radii are checked. Interior reservations are valid and use their scene's local coordinate space.
- The three canonical portals must pair the correct interior `entry` with its exterior return entrance. Missing destinations, wrong but existing destination scenes, invalid trigger sizes, and returns less than 1.5 meters from the horizontal trigger bounds fail.
- Rest points, discovery radii, viewpoint targets, entrance facing angles, the exterior start/safe anchor, and duplicate world IDs are checked. Exterior positions must remain inside the authored horizontal bounds.
- Terrain grid dimensions must tile exactly; terrain/navigation dimensions, pond radii/depth, seed, and decoration counts must be valid. Deep-water ellipses require finite centers, positive radii, and ordered vertical limits. Bounds require ordered axes and matching horizontal map limits.

This supports R04 data rejection and the manifest portions of R05/R06/R10/R11. It does not prove physical reachability, safe collision occupancy, navigation readiness, persistent discovery, or recovery behavior.

## Changed files and contracts

- `core/exterior_validation.gd`: global `ExteriorValidation` helper and the public method above. Uses existing `SessionValidation` and `ExteriorLandmarks` helpers.
- `tests/unit/test_world_manifest.gd`: canonical pass, input immutability, JSON numeric decoding, broken-link and malformed-value mutations.
- `docs/handoffs/T10-validation.md`: this handoff.

No shared loader, base validator, map, exterior runtime, or gameplay file was edited. Registries are the loaded `ContentDB.containers` and `ContentDB.dialogues` dictionaries. Scene references use `map.scenes`; no runtime filesystem check requires unfinished interior scenes to exist. Existing base validation continues to own item, landmark-count, hostile-count/composition, and loot checks.

## Verification actually performed

Pinned engine: `4.5.2.stable.official.6ce3de25a` on the provided macOS host.

```sh
"$HOME/.local/share/mireward-tools/godot-4.5.2/Godot.app/Contents/MacOS/Godot" \
  --headless --path . --script res://tests/run_all.gd -- \
  --suite=unit/test_world_manifest.gd
```

Final result: **233 assertions, zero failed suites**, exit 0, no engine/script errors. The suite includes null, boolean, array, dictionary, and NaN replacements at nested schema boundaries; infinity and invalid-dimension fixtures; duplicate identities within and across sections; missing/wrong destinations; absent reservation targets; and out-of-bounds exterior returns. The first run exposed an unsafe mixed-type comparison for a malformed scene ID. Guarding the types corrected it before the final successful run.

The new file diffs were reviewed. No broad test suite, graphical session, network request, or Git mutation ran for this subtask.

## Successor instructions and remaining gaps

Call `ExteriorValidation.validate(map, containers, dialogues)` after the container/dialogue registries have loaded and before accepting the map for construction; append its errors to the existing content diagnostics. Also include it in the content-validation command. Do not call this complete-reference check before loading those registries, because it intentionally rejects missing targets.

The focused test uses an explicit preload, so it can execute before the new global class is imported. The usual pinned editor import registers the class for shared-validator calls. Integration owner should run the focused content/foundation checks after wiring and commit/push this bounded batch with the exterior checkpoint. T11/T17 and the later release gates still own actual scene transitions, hazards, target instantiation, and playable traversal verification.
