# Implementation decisions

- 2026-09-21: The root specification files remain canonical. Preserve their locations and links.
- The user goal overrides tasks.md's sequential scheduling rule. Dispatch only ready tasks, with exclusive file ownership; integration and verification still gate dependents.
- Registries use committed JSON. Typed GDScript wrappers expose immutable definitions. Mutable session state uses JSON-safe dictionaries and stable string identifiers.
- All cross-domain mutations stage a detached state through Transactions. Failure discards the candidate; successful receipts persist and replay without new events.
- Five autoloads only: ContentDB, EventBus, GameSession, SaveService, AudioService. Other services belong to GameSession or GameRoot.
- No remote publishing, external gameplay services, purchased assets, or Blender dependency.

- Engine/environment verified at Godot 4.5.2.stable. Enable ETC2/ASTC imports for universal/arm64 macOS export as required by the pinned exporter.
- T03 exposes `VisualFactory.pose(actor, state, phase=0, intensity=1)` and `pose_gear(root, state, phase)`. Combat phases normalize phase to 0..1; idle/walk use radians. Gear origin is grip, blade +Y, forward -Z. Gameplay owns timing.
- Foundation quest/dialogue registries reserve canonical IDs with `foundation_only=true`; release validation refuses them. T12/T13 replace them with complete data rather than inventing new IDs.
- User explicitly requests ongoing commits and pushes. Review each staged integration diff, commit a coherent batch, and push fix/mireward-game after the relevant checks. Keep unfinished task state visible; do not wait for the whole game before pushing.
