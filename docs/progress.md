# Execution queue

Complete specification scope is authorized. The user objective overrides sequential scheduling only; dependencies, integration gates, and all mandatory requirements remain active.

| Task | State | Owner | Next gate |
|---|---|---|---|
| T01 | VERIFIED | Integration lead + environment | Foundation import and visible shell verified; handoffs/T01.md |
| T02 | VERIFIED | Integration lead + foundation_audit | 48 foundation and 11 math assertions; handoffs/T02-audit.md |
| T03 | VERIFIED | visual_toolkit + integration lead | 748 art assertions, byte-identical regeneration and three inspected 540p views |
| T04 | IMPLEMENTED | Integration lead | 12 movement assertions pass and real W movement inspected; finishing camera/gear check |
| T05 | IN_PROGRESS | foundation_audit | Interaction occlusion, modal pause/cursor and input-release tests |
| T06 | IN_PROGRESS | environment | Consumes verified player and import-tested T05 APIs; combat fixtures pending |
| T07 | NOT_STARTED | Unassigned | T03/T06 integrated |
| T08 | NOT_STARTED | Unassigned | T02/T05/T06 integrated; parallel with T07 |
| T09 | NOT_STARTED | Unassigned | T07/T08 integrated |
| T10 | NOT_STARTED | Unassigned | T03/T05/T07 integrated; parallel with T09 |
| T11 | NOT_STARTED | Unassigned | T09/T10 integrated |
| T12 | NOT_STARTED | Unassigned | T02/T08/T09 integrated; parallel with T11 |
| T13 | NOT_STARTED | Unassigned | T05/T12 integrated |
| T14 | NOT_STARTED | Unassigned | T09/T11/T12/T13 integrated |
| T15 | NOT_STARTED | Unassigned | T10/T13/T14 integrated |
| T16 | NOT_STARTED | Integration lead | Playable opening integration, then continue full campaign |
| T17–T28 | NOT_STARTED | Unassigned | Dispatch against tasks.md dependencies after opening integration |

## Exclusive ownership

- visual_toolkit: T03 finished; art files returned to integration lead.
- foundation_audit: T05 interaction component/ray, mode controller, modal host, related integration tests and T05 handoff. T02 files returned to lead.
- Integration lead: T04 player code/scene/movement tests, root configuration, autoloads/core, shared records, integration and checkpoints.
- environment: T06 scripts/combat, combat fixtures/arena, T06 handoff.

## Resume

Read this file, decisions.md, verification.md, relevant handoffs, and git status. Continue existing work. Goal is the entire campaign, all side quests/endings/aftermath, real gameplay verification, and host build. No publication. Never treat a reserved content ID or passed domain test as a completed playable requirement.
