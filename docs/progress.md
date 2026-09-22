# Execution queue

Complete specification scope is authorized. The user objective overrides sequential scheduling only; dependencies, integration gates, and all mandatory requirements remain active.

| Task | State | Owner | Next gate |
|---|---|---|---|
| T01 | VERIFIED | Integration lead + environment | Foundation import and visible shell verified; handoffs/T01.md |
| T02 | VERIFIED | Integration lead + foundation_audit | 48 foundation and 11 math assertions; handoffs/T02-audit.md |
| T03 | VERIFIED | visual_toolkit + integration lead | 748 art assertions, byte-identical regeneration and three inspected 540p views |
| T04 | IMPLEMENTED | Integration lead | 12 movement assertions pass and real W movement inspected; finishing camera/gear check |
| T05 | IMPLEMENTED | Integration lead | 33 interaction/mode assertions pass; production graph/native checks at T11/T15 |
| T06 | IMPLEMENTED | Integration lead | 79 unit +26 spatial assertions; full suite958 pass; final combat feel/audio later |
| T07 | IMPLEMENTED | Integration lead | Root67 enemy assertions pass; native world/loot integration later |
| T08 | VERIFIED | Integration lead | 130 inventory/equipment/loot assertions; physical UI/world wiring later |
| T09 | IMPLEMENTED | Integration lead | 107 unit +44 physics assertions; campaign travel/UI/save wiring later |
| T10 | IMPLEMENTED | Integration lead | Exterior634 assertions, route walks and baseline captures; final dressing later |
| T11 | IMPLEMENTED | Integration lead | Travel612, presentation19 and modes45; campaign UI wiring later |
| T12 | IMPLEMENTED | Integration lead | Root619 quest assertions; physical campaign/UI wiring later |
| T13 | IMPLEMENTED | Integration lead | Root598 dialogue assertions; native UI and placement later |
| T14 | IN_PROGRESS | save/lifecycle owner | Codec264 and composed lifecycle46 pass; final failure/queue checks underway |
| T15 | IN_PROGRESS | quest_engine | Native menus/HUD over verified domain and save interfaces |
| T16 | NOT_STARTED | Integration lead | Playable opening integration, then continue full campaign |
| T17–T28 | NOT_STARTED | Unassigned | Dispatch against tasks.md dependencies after opening integration |

## Exclusive ownership

- T11 world routing/interiors returned and integrated.
- quest_engine: T15 native UI, HUD, settings, inventory/shop/loot and journal/map panels.
- world_validation/npc_adapter: T14 SaveService, codecs, settings and save tests; T13 ownership returned.
- Integration lead: shared configuration/autoload/core wiring, GameRoot/UI integration, returned T09/T10 code, records and all Git operations.

## Resume

Read this file, decisions.md, verification.md, relevant handoffs, and git status. Continue existing work. Goal is the entire campaign, all side quests/endings/aftermath, real gameplay verification, and host build. No publication. Never treat a reserved content ID or passed domain test as a completed playable requirement.
