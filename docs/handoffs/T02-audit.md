# T02 audit and boundary repairs

Status: VERIFIED for the foundation scope below.
Repository checkpoint: shared working tree, uncommitted; integration owner retains commit responsibility.

## Ranked findings and repairs

1. **P1: raw content reached typed constructors before validation.** A definition containing only an ID passed the loader and then accessed missing fields in `MireTypes`. `autoload/content_db.gd:56` now validates each row before construction. `ContentValidation.definition` checks required fields, enum values, numeric domains, phase arrays, and equipment stack limits. The world manifest is checked before exposure, including duplicate IDs, scene links, and entrance transforms. Reload clears stale map/shop data. Canonical registry checks now require the frozen item, enemy, quest, and dialogue IDs, not only their counts.
2. **P1: damaged receipts and callback failures could abort transactions.** Replay trusted arbitrary dictionary members and a callback returning null left the transaction lock active. `core/transactions.gd:15` now rejects malformed ledgers/receipts; invalid callables and wrong/null results return `invalid_transaction` without retaining the lock. Replay validates the saved receipt and returns its detached result without executing the supplied callback.
3. **P1: tests could report success after script errors.** The old runner counted explicit assertions only. `tests/run_all.gd:45` now runs each suite in a child engine process and requires a successful exit, an assertion summary, at least one assertion, and no engine/script error output. Parse failures, runtime failures, and failed assertions are exercised as deliberate child-process fixtures and all return nonzero.
4. **P2: commit boundaries leaked mutable aliases and accepted unsafe receipt payloads.** The old coordinator validated state before inserting the receipt and assigned the staging dictionary directly. It now inserts and validates the receipt before commit, detaches committed state and returned payloads, rejects historical ledger edits, and validates notification names/argument signatures before mutation. A retained staging dictionary or returned nested payload can no longer change live inventory.
5. **P2: restore accepted malformed nested sections.** `core/session_validation.gd` now checks the complete value tree for JSON-compatible values, finite numbers, string dictionary keys, and bounded nesting. It validates quest record shapes and known quest IDs, choices, flags, discovery IDs, pending item IDs/counts, receipts, transforms, stack identity allocation, and shop stock. Equipment stock cannot change to the unlimited-consumable sentinel. Invalid restore candidates leave the live session unchanged.

## Contracts preserved and added

All existing public methods and successful initial-state behavior remain unchanged. Transactions still accept `run(transaction_id, stage)` with a one-argument staging callable returning `MireTypes.ActionResult`. Replaying an existing ID does not need a valid callback because the callback is not invoked. Failure codes remain `invalid_transaction`, `invalid_state`, and `busy`.

Persistent data uses JSON values and string keys. Convert transient `StringName` IDs to strings when adding them to state or receipt payloads. Event arguments may use `StringName` as specified by EventBus. Only the transaction coordinator writes the completed receipt ledger. A transaction stages notifications through `ActionResult.event`; invalid signals or argument counts/types reject the transaction before committing.

Test suites retain `extends RefCounted`, `run(t: SceneTree)`, and `t.check(condition, requirement_or_fixture_description)`. Each child receives a unique `MIREWARD_TEST_SAVE_DIR` environment variable before autoload initialization. Suites can also access `t.test_save_directory`. T14 must route test SaveService paths through this override. Tests must not touch production slots. The parent removes its isolated directories afterward. A focused suite can be selected with `-- --suite=unit/test_foundation.gd`. Awaited suites have a 120-second timeout.

Owned changes: `core/session_validation.gd`, `core/content_validation.gd`, `core/transactions.gd`, `autoload/content_db.gd`, `tests/run_all.gd`, `tests/unit/test_foundation.gd`, and this handoff. No other source, manifest, shared progress record, or commit was changed by this task.

## Verification actually performed

Engine: Godot `4.5.2.stable.official.6ce3de25a` on the provided macOS host. Commands were run from the repository root using the pinned engine binary.

- `Godot --headless --path . --editor --quit`: passed import with no script errors after final changes.
- `Godot --headless --path . --script res://tools/validate_content.gd`: passed foundation content validation, covering 23 items, 5 enemy types, 12 quest IDs, 8 speakers, 9 landmarks, and 26 hostile spawns.
- `Godot --headless --path . --script res://tests/run_all.gd`: passed 459 assertions across the then-current art, combat-math, and foundation suites.
- `Godot --headless --path . --script res://tests/run_all.gd -- --suite=unit/test_foundation.gd`: passed 48 foundation assertions after the final canonical-ID check.
- `Godot --headless --path . --script res://tools/validate_content.gd -- --release`: correctly exited 1 for the twelve reserved quests, eight reserved dialogues, and missing icon resources. This is an expected release failure, not completed-content evidence.
- A subsequent full rerun discovered the newly added movement integration suite: 470 assertions, one failed suite, exit 1. The failure was `R07 mouse pitch clamps to minus 85 degrees` in `tests/integration/test_movement.gd`. Reported immediately to the integration owner; movement source is outside this task ownership. The foundation suite remained passing.
- Deliberate assertion, malformed script, and runtime array-index failure fixtures each produced nonzero exits from the public runner. Their output was captured by the foundation suite and temporary files were removed.

## Successor scope and remaining gates

This establishes safe foundation shapes and transaction boundaries. It does not claim the R04, R23, or R49 release requirements are complete.

T12/T13 must add complete quest objectives, registered evidence/conversation/pickup identities, dialogue graph validation, predicate/effect whitelists, and cross-reference validation for physical objective targets. World records currently require nonempty identities and dictionary values; the full persistent-object registry is not yet authored. Objective record contents and quest completion prerequisites deliberately remain with their owning modules.

T08/T09/T14 must extend semantic validation for concrete loot/container records, claimed versus pending deliveries, shop completeness, choice-versus-quest consistency, save envelopes, and failure recovery once those services exist. The current schema supports the specified pending-delivery records `{item_id, quantity}` and shop counts including `-1` only for originally unlimited stock.

Reserved `foundation_only` quest/dialogue entries are valid T02 registry reservations. Removing that flag alone is not proof of functional story content. Release-mode failure remains required until the owning tasks implement and validate that content. No gameplay, visual, persistence-write, or export gate was claimed by this audit.
