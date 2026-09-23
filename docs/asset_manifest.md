# Original visual assets

The models, materials, textures and icons below were authored locally for MIREWARD. No asset packs, photographs, downloaded models, or external textures are used. Author: MIREWARD project contributors. License: CC0-1.0, recorded in `assets/LICENSE.txt`. No attribution is required for that original artwork. The generation source is the editable original; modifications are the meter-scale assemblies, palette, icons, textures, and rigid poses described here. The embedded engine font has its own third-party notice below.

| Output family | Stable paths | Original source | Contents |
|---|---|---|---|
| Characters | `assets/models/actors/*.tscn` | `scripts/art/art_actors.gd` | 12 archetypes covering four ordinary enemies, Rusk, and all eight named speakers including Rusk |
| Gear and quest items | `assets/models/gear/*.tscn` | `scripts/art/art_gear.gd` | All 23 item registry IDs; internal spear and keeper mace assemblies also available through the factory |
| Architecture | `assets/models/buildings/*.tscn` | `scripts/art/art_buildings.gd` | 15 reusable building and interior families |
| Nature and props | `assets/models/props/*.tscn` | `scripts/art/art_props.gd` | 30 prop families, including story chests, three chimes, writ table, shrine, banners, door and loot purse |
| Materials | `assets/materials/*.tres` | `scripts/art/art_mesh.gd` | 21 shared palette materials, roughness 0.66 for metal and 0.92 for other surfaces |
| Item icons | `assets/icons/*.svg` | `tools/generate_assets.gd` | 23 original 128px vector icons at the exact registry paths |
| Small textures | `assets/textures/*.png` | `tools/generate_assets.gd` | Five deterministic 128px images: stone, timber, linen, parchment and palette atlas |
| Rigid poses | `scripts/art/visual_factory.gd` | Same file | Actor idle, walk, windup, attack, block, stagger, death, captain phase stance/thrust/sweep; first-person idle/light/heavy/guard/parry recoil/healing |
| Review scene | `scenes/art/showcase.tscn` | `scripts/art/showcase.gd` | Late-afternoon exterior and separate furnished crypt review stage |
| Interaction details | Runtime world assemblies | `scripts/world/world_object.gd`, `scripts/world/world_interactions.gd` | Offering bowl, document stands, crate lid and matching solid rest-lantern supports, using the same original geometry and materials |

Original audio sources, reproduction and verification limits are recorded in `docs/audio_manifest.md`; runtime mix acceptance is tracked separately from visual art.

## Embedded runtime font

The pinned Godot 4.5.2 runtime embeds Open Sans SemiBold 1.10 under Apache-2.0. Its [pinned font manifest](https://github.com/godotengine/godot/blob/4.5.2-stable/thirdparty/README.md#fonts) identifies the February 2021 Google Fonts source and TTF-to-WOFF2 conversion. The font's own name records say: `Digitized data copyright © 2011, Google Corporation.` Manufacturer: Ascender Corporation. No project modification or extra font binary is involved.

On 21 September 2026 UTC, the active fallback font reported `Open Sans SemiBold / SemiBold`; its 46,392 bytes exactly matched the [pinned source WOFF2](https://github.com/godotengine/godot/blob/4.5.2-stable/thirdparty/fonts/OpenSans_SemiBold.woff2), SHA-256 `661e2d9975d3029aeb32bf37b1b963c31c7c3ce08ac1bab2c8ebe27e135c4ec2`. The metadata also explicitly names Apache License 2.0. This evidence concerns the game runtime font, not the editor's Noto fonts or newer Open Sans versions.

Retain `assets/fonts/NOTICE-OpenSans.txt` and `assets/fonts/LICENSE-OpenSans-Apache-2.0.txt` in release artifacts. The notice contains exact name records and source links; the license is an unchanged copy from the Apache Software Foundation. Export inclusion filter: `assets/fonts/*.txt`. Release packaging must make both files available with the existing third-party notices.

## Scale and art contract

One unit is one meter. Model origin is at ground level; forward is -Z. Adults stand approximately 1.85 m, with Rusk scaled by 1.055. Gear origin is its grip, with blades along +Y and shield faces toward -Z. House floors are 0.12 m above origin; door openings provide at least 1.6 m width and 2.38 m clear height over that floor. Gate opening is 3 m. The bridge is 3 m wide and 10 m long. See `docs/handoffs/T03-buildings.md` for each architecture footprint and placement caveat.

Palette anchors: peat #242B28, fog #A8B2AA, stone #68736B, reed #777844, rust #824D3C, warm #E1B978, parchment #D8CEB1. Texture sampling is nearest with mipmaps. World triplanar textures repeat every 2 m, with linen repeating every 0.5 m. Icons render at native UI resolution. Static buildings and props combine their geometry by material; chest lids retain their own pivot. Visual roots own no collisions, interaction state, inventory, or gameplay timing.

Medicine-chest bodies and lids use muted blue paint #496F94 to match the authored blue-box clue. Iron trim, parchment plaque and the red medical symbol retain their existing materials. The palette atlas expands its row count with the named palette; other chest families remain wood. Rest lanterns retain their authored positions on small matching supports; their canonical recovery anchors are unchanged.

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
