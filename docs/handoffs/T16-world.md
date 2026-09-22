# T16: Opening world population

Status: VERIFIED detached factory and focused headless opening integration. Native opening acceptance remains root-owned.
Repository checkpoint: root owns review, commits and pushes.

## Delivered

`scripts/world/campaign_world.gd` defines `CampaignWorld(player: MirePlayer)`, a reusable factory for the existing WorldRouter. It adds only the opening content. Exterior has Mara, Oswin, the training dummy, southern sign, cart medicine coffer, robbed cart and two canonical south_cart cutpurses with one EncounterCoordinator. The inn has Tamsin. Other scenes remain available through the existing router without later campaign population being claimed.

```gdscript
var campaign := CampaignWorld.new(player)
router.world_builder = campaign.build
# In world_activated, after activating NPC/WorldObject/TrainingDummy adapters:
campaign.activate(world)
```

`build(world, detached_candidate) -> ActionResult` creates one scene-owned `OpeningPopulation`, rejects duplicate installation and registers canonical entities. NPCs configure with live=false. WorldObjects configure against the candidate. Saved enemy defeat/disabled state applies before navigation checks. The factory neither binds global/player listeners nor mutates GameSession during preparation. It uses the existing player; it never creates another.

`activate(world) -> ActionResult` connects death/danger hooks once. Scene exit disconnects those hooks; explicit reactivation after rollback reconnects once. The router remains responsible for binding live EnemyActor and EncounterCoordinator player references. Root's generic activation handles NPCs, WorldObjects and the TrainingDummy.

A live enemy death commits WorldStateService.mark_defeated for that canonical spawn. Its nonblocking WorldObject purse is a world sibling, placed beside the actual death and grounded by a world ray. The actor retains world.entities[spawn_id]; the purse shares that source rather than inventing another persistent identity or reward. Death grants no crowns. Looting claims the authored four crowns once and hides the empty purse. Reconstruction keeps defeated actors dead, resets living actors and preserves remaining/depleted loot. Reconstructed corpse presentation uses the canonical spawn station; transient death positions are not persisted.

## Placement and navigation

NPC and coffer coordinates come unchanged from map reservations:

| Object | Position | Facing |
|---|---|---|
| Mara | (-107, 0, 143) | South |
| Oswin | (-99, 0, 135) | South |
| Tamsin | (-3, 0, -2), inn | East |
| Medicine coffer | (0, 0, 105) | North |
| Cutpurses | (-2, 0, 100), (3, 0, 100) | Manifest yaw |
| Training dummy | (-97, 0, 137) | South, within Oswin's cleared reservation |
| Southern sign | (30.6, 0, 248.5) | Toward the starting approach |
| Robbed cart | (3.8, 0, 106) | North |

The cart uses existing VisualFactory art with bed/wheel-envelope and narrow shaft colliders. A static NavigationObstacle3D with radius 2 m, height 1.5 m and center offset (0,0,-0.7) supplies local agent avoidance. No map manifest, prebaked navigation asset or navigation hash was changed. No runtime rebaking is performed. Normal-physics chase around this actual placed cart passed.

## Verification actually performed

Pinned Godot `4.5.2.stable.official.6ce3de25a` on macOS:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/run_all.gd -- --suite=integration/test_opening_world.gd
```

Import passed. Final opening suite: **149 assertions, zero failed suites**.

Coverage includes detached candidate defeat/depleted-purse presentation; unchanged current snapshot; no prepared global/player subscriptions; duplicate-builder refusal; exact opening entity/player counts; all exterior entrances and rest anchors; grounded navigable NPC/training/coffer approaches; actual InteractionRay focus on sign, dummy, Mara and coffer; ordinary MQ01 acceptance/pickup/once-only return; early medicine with a full normal inventory and pending reward; exact 18-crown payment and MQ02 unlock; retained acquisition evidence; normal-physics cutpurse movement around cart; actual CombatComponent death and sibling purse position; once-only four-crown loot; real manual save-file validation/load; dead/living/coffer reconstruction; blocked final-arrival rollback with original world/snapshot/listener restoration; two inn round trips; Tamsin bed clearance; and listener teardown.

The fixture positions the player to isolate interactions and enters AI chase directly to test steering. Inventory fullness uses valid domain additions. Death exercises the actual combat receiver, not an unassisted sword duel. These are integration fixtures, not native campaign playthrough evidence, travel-time measurements or visual acceptance.

## Root continuation

The production graph can now offer the opening loop through its existing UI: start on the south road, read the sign, follow the road into Brackenford, accept Mara's medicine contract, optionally use Oswin's training target, take the cart track east, fight or bypass the two cutpurses, open and loot the coffer, return to Mara, receive the reward, and visit Oswin/Tamsin for shop/rest/save checks.

Root owns native normal-control execution, screenshots, route pacing, death/full-inventory/reload acceptance through UI, and any shared runtime corrections. T17 adds the remaining world content after that opening integration gate. This task changed only the factory, its focused test and this handoff (plus engine-generated UIDs), and made no Git mutations.
