# Brig merge pipeline  (Master.blend -> Godot `Brig.glb`)

Rebuilds the game version of the merchant brig from `MerchantBrigShipMaster.blend` in about 40 seconds.
No texture baking: materials use Poly Haven maps **pre-tinted into JPGs** (same method as the town).
Master is never modified. `export/Brig.glb` is never overwritten (the test file is `export/Brig_test.glb`).

## Run it
From the project root, either:

    "C:\Program Files\Blender Foundation\Blender 4.1\blender.exe" -b --python tools/brig_merge/run_all.py

or inside an open Blender session: `exec(open(r"<project>/tools/brig_merge/run_all.py").read())`.
Every step is a **separate background Blender process**, so a crash cannot take your session down.
Progress prints one line per step; per-step logs are `tools/brig_merge/*_log.txt` (last `START <object>` line = where a crash happened).

## Files
| Path | What |
|---|---|
| `tools/brig_merge/00..08_*.py`, `merge_lib.py`, `run_all.py` | the pipeline |
| `tools/brig_merge/game_groups.json` | which Master objects join which merged mesh (Hull, DeckFittings, Rig_Spars, Rig_Ropes, Interiors, ...) |
| `tools/brig_merge/game_assign.json` | which loose parts of Yards_*/YardBands_*/Footropes/Stirrups/Blocks belong to which yard |
| `tools/brig_merge/old_meta.json` | pivots/props of the shipped brig (yard/sail/gun/door/rudder/wheel origins, ship-root data, light props) |
| `tools/brig_merge/source/MerchantBrigShipGame_source.blend` | **frozen** copy of the old Game.blend: source of the sail + flag meshes (PinWeights colours + Furled/Reefed shape keys) and of the base collision meshes |
| `tools/brig_merge/out/sNN_*.blend` | result of each step; `s07_collision.blend` is the finished game file |
| `textures/polyhaven/export/` | pre-tinted diffuse JPGs (`EX_*`) + generated flag PNGs |

## Steps
| # | Script | Does |
|---|---|---|
| 00 | `00_materials.py` | `PH_*` materials -> export-clean `M_Brig_*` (tint baked into a JPG, roughness + normal kept). Ropes/tar/parchment/burlap -> flat colours. Flags -> generated textures. Sails/flags get Base Color = image x Color Attribute `PinWeights` (needed so Blender 4.1's glTF exporter writes `COLOR_0`). |
| 01 | `01_static_groups.py` | bakes modifiers and joins objects into `Hull, MainDeck, DeckFittings, DeckExtras, Rig_Spars, Rig_Ropes, Interiors` (+ ship root `Brig` with the old ship-level props: class, crew, waterline table, rig json). |
| 02 | `02_animated_parts.py` | builds the parts Godot moves, with the shipped names/pivots: `Rudder, Wheel, Door_Cabin, Door_Room_Port/Stbd, Gun_0..5 (+_Barrel child), Yard_Fore/Main_0..2`. Appends the shipped sails + flags from the frozen source, gives them new tiled UVs + materials, parents sails to their yards. |
| 03 | `03_organize.py` | fixes `.001` names, moves hammock sets / pump / log line / bookshelf+books / station + sink + camera markers / lights into `Brig_Export` (lights get their old Godot props), parks every source object in the hidden `Brig_Source`. |
| 04 | `04_decimate.py` | decimates the merged meshes to the old budget (Hull 55%, Interiors 55%, DeckFittings 58% with rope faces kept, Rig_Spars 55%, Rig_Ropes 33%, Wheel 40%, guns 42%). |
| 05 | `05_rig_lods.py` | `Rig_LOD1` (60-250 m, ~6.8k tris) and `Rig_LOD2` (250 m+, ~3.4k) with flat-colour materials. |
| 06 | `06_finalize.py` | no hull LOD yet -> Hull/MainDeck/DeckFittings visible at any distance. |
| 07 | `07_collision.py` | the six old `Col_*-colonly` meshes; old centre-pump boxes removed; boxes added for the new pump, both bunks, bookshelf, galley barrel. |
| 08 | `08_export_test.py` | glTF export (GLB, modifiers applied, extras, lights, morph targets) to `export/Brig_test.glb`. |

## What Godot expects (`brig_import.gd`)
* Node names: `Hull, MainDeck, DeckFittings, DeckExtras, Rig_*, Interiors, Rudder, Wheel, Door_*, Gun_N / Gun_N_Barrel, Yard_<Mast>_<N>, Sail_*, Flag_*, Col_*-colonly / -convcolonly, LT_*`.
* Custom props become glTF extras: `game_role`, `vis_begin/vis_end`, `interaction`, light `godot_*`. New roles: `hammock_set, hammock, hammock_slot, station, sink_check, camera_marker` (any other role -> group `role_<name>`).
* Sails/flags: `COLOR_0` = PinWeights (r billow, g height, b across) and shape keys `Furled` / `Reefed`. Their UVs are **tile units** (0.5 m), so `sail_wind.gdshader` needs `repeat_enable` on `albedo_tex` (already there).

## Changing the brig later
* **New small interior/deck object** (static): just model it in Master. Objects named in `game_groups.json` are picked up automatically; a *new* name must be added to a list: interiors -> `extra_interior` in `01_static_groups.py`, deck -> `extra_deck`.
* **New interactive/animated object** (must stay its own node): name it with a prefix from `KEEP` in `03_organize.py` (`HammockSet_, Station_, Pump, LogLine, CabinBookshelf, Book_, ...`) or add a prefix there; set `game_role` / `interaction` custom props in Master.
* **New material**: use a `PH_*` material with a `Tint` node (or a flat Principled one). Procedural node trees will NOT export - step 00 only converts the ones it knows (see `rep` in `00_materials.py`).
* **New collision**: add its bounding box in `07_collision.py` (`want` list).
* **Changed sails**: the shapes come from the frozen source. If the sails are remodelled, regenerate Furled/Reefed + PinWeights and update `source/..._source.blend`.

## Gotchas learned (do not repeat)
* **Blender 4.1 crashes** if you evaluate objects (`evaluated_get`/`new_from_object`) *after* the scene was changed in the same session. All steps therefore **read/bake everything first, then create** (and decimate: add all modifiers first, evaluate all, then swap meshes).
* `evaluated_object.material_slots` points at temporary copies that vanish when the file is saved -> always read materials from the **original** object.
* Read mesh data with `foreach_get` / attributes, not per-element RNA, and read UVs via the `UVMap` attribute.
* This Blender build has **no Cycles bake**; flags are generated with numpy.
* glTF exporter (4.1) writes vertex colours only if the material multiplies the base colour by a Color Attribute node.
* **Ropes must not be collapse-decimated.** Collapse at 33% turned thin curved ropes (ratlines, seizings, shroud ends) into angular, kinked strips in Godot. `04_decimate.py` keeps every rope piece aft of `ROPE_FULL_Y` (main mast, backstays, spanker: what you see from the poop deck) at full shape (limited dissolve only, Rig_Ropes ~14.8k -> ~23k tris); forward ropes are still collapsed. Set `ROPE_FULL_Y = -999` for the whole ship (~30k tris).
* Decimate on the thin double-skinned hull wrecks it below ~50%; voxel remesh is ragged. See TODO.

## Known gaps / TODO
* **Hull LODs** (Hull_LOD1/2) are not built; the full 49k-tri hull draws at all distances. Idea: LOD from the original low-subdivision hull parts (solidify only), not from the decimated merge.
* No collision for hammock frames/posts or the folding room tables.
* `DeckFittings` is ~30k tris (old ~21k): rope faces there are not reduced.
* Ropes are flat colours (no twist texture).
* 8 hammock modules, pump, log line etc. keep their modifiers; the exporter applies them.

## Putting it in the game
1. Back up `uncharted-oceans/assets/ships/brig/Brig.glb` (the old one is also `Brig.glb.bak-2026-10-19`).
2. Copy `export/Brig_test.glb` over it, select it in Godot -> Import tab -> Import Script = `brig_import.gd` -> Reimport.
3. Check: sails billow + reef, flags, guns, doors, hammock sets, stations in groups, collision (walk the decks, bunks, pump, shelf), lights.
4. When it checks out: copy `tools/brig_merge/out/s07_collision.blend` over `MerchantBrigShipGame.blend` (keep the frozen source in `source/`).

## Status
* 2026-10-21: `export/Brig_test.glb` is installed in Godot as `assets/ships/brig/Brig.glb` (old one kept as `Brig.glb.bak-2026-10-21`). `MerchantBrigShipGame.blend` is still the OLD game file until the new brig is checked in Godot; then replace it with `out/s07_collision.blend`.
* `out/` is generated (gitignored); only `s07_collision.blend` is kept between runs, `run_all.py` recreates the rest.
