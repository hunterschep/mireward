# Original visual assets

All visual artwork below was authored locally for MIREWARD. No asset packs, photographs, downloaded models, or external textures are used. Author: MIREWARD project contributors. License: CC0-1.0, recorded in `assets/LICENSE.txt`. No attribution is required. The generation source is the editable original; modifications are the meter-scale assemblies, palette, icons, textures, and rigid poses described here.

| Output family | Stable paths | Original source | Contents |
|---|---|---|---|
| Characters | `assets/models/actors/*.tscn` | `scripts/art/art_actors.gd` | 12 archetypes covering four ordinary enemies, Rusk, and all eight named speakers including Rusk |
| Gear and quest items | `assets/models/gear/*.tscn` | `scripts/art/art_gear.gd` | All 23 item registry IDs; internal spear and keeper mace assemblies also available through the factory |
| Architecture | `assets/models/buildings/*.tscn` | `scripts/art/art_buildings.gd` | 15 reusable building and interior families |
| Nature and props | `assets/models/props/*.tscn` | `scripts/art/art_props.gd` | 30 prop families, including story chests, three chimes, writ table, shrine, banners, door and loot purse |
| Materials | `assets/materials/*.tres` | `scripts/art/art_mesh.gd` | 20 shared palette materials, roughness 0.66 for metal and 0.92 for other surfaces |
| Item icons | `assets/icons/*.svg` | `tools/generate_assets.gd` | 23 original 128px vector icons at the exact registry paths |
| Small textures | `assets/textures/*.png` | `tools/generate_assets.gd` | Five deterministic 128px images: stone, timber, linen, parchment and palette atlas |
| Rigid poses | `scripts/art/visual_factory.gd` | Same file | Actor idle, walk, windup, attack, block, stagger, death, captain phase stance/thrust/sweep; first-person idle/light/heavy/guard/parry recoil/healing |
| Review scene | `scenes/art/showcase.tscn` | `scripts/art/showcase.gd` | Late-afternoon exterior and separate furnished crypt review stage |

Audio is tracked separately by its owning task. No audio provenance or completion is implied by this visual manifest.

## Scale and art contract

One unit is one meter. Model origin is at ground level; forward is -Z. Adults stand approximately 1.85 m, with Rusk scaled by 1.055. Gear origin is its grip, with blades along +Y and shield faces toward -Z. House floors are 0.12 m above origin; door openings provide at least 1.6 m width and 2.38 m clear height over that floor. Gate opening is 3 m. The bridge is 3 m wide and 10 m long. See `docs/handoffs/T03-buildings.md` for each architecture footprint and placement caveat.

Palette anchors: peat #242B28, fog #A8B2AA, stone #68736B, reed #777844, rust #824D3C, warm #E1B978, parchment #D8CEB1. Texture sampling is nearest with mipmaps. World triplanar textures repeat every 2 m, with linen repeating every 0.5 m. Icons render at native UI resolution. Static buildings and props combine their geometry by material; chest lids retain their own pivot. Visual roots own no collisions, interaction state, inventory, or gameplay timing.

## Catalog IDs

`ArtActors.ARCHETYPES`, `ArtBuildings.FAMILIES`, and `ArtProps.KINDS` expose the complete supported IDs. Gear uses `data/items/items.json`, with `spear` and `keeper_mace` as actor-only additions.

Building IDs: cottage, inn, forge, road_gate, wall, keep, monastery_arch, monastery_tower, crypt_room, undercroft_room, bridge, ferry, ruined_watchtower, tent, kiln.

Prop IDs: oak, pine, reeds, rock, cart, chest, medicine_chest, ledger_chest, badge_locker, seal_chest, writ_table, reed_chime, stone_chime, flame_chime, shrine, banner_crown, banner_valley, banner_free, sign, toll_notice, corpse_loot, barrel, crate, well, lantern, door, bed, bench, sack, candle.

## Reproduction

Use the Godot version pinned in `.godot-version`. Existing committed assets require only normal editor import. To regenerate from the authored source:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tools/generate_assets.gd
godot --headless --path . --editor --import --quit
```

When reconstructing after deleting all generated textures and import metadata, run the generator once before these commands to create the texture source, then use the normal sequence. Stable resource IDs prevent regenerated scene text from changing merely because object IDs changed.

Review with `godot --path . res://scenes/art/showcase.tscn`. Append `--resolution 960x540 -- --capture` to save exterior, knight close-up and interior images into `tests/output/art/` and exit. This fixture does not replace the final game's lighting, collision, combat animation synchronization, or release-view review.
