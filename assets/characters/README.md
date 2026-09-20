# Characters

Primitive-built, procedurally animated characters for *Man v Man v Food*.
No external assets, no skinning: every character is a hierarchy of `Node3D`
pivots and `MeshInstance3D` primitives (Box/Sphere/Cylinder), animated by
`character_rig.gd` every frame.

| File | What |
|---|---|
| `character_base.tscn` | The full rig with every accessory (hidden by default). 37 mesh nodes. |
| `character_rig.gd` | `class_name CharacterRig` - animation, recolouring, accessory toggles. Attached to the base root. |
| `player.tscn` | The YouTuber: cap, hoodie, shorts, sneakers, chest action-cam with red REC light. |
| `chef_owner.tscn` | Angry restaurant owner: toque, apron, angry brows, kitchen knife in the right hand. |
| `rival_creator.tscn` | Rival creator: headband, sunglasses, magenta/neon palette. |
| `preview.tscn` / `preview.gd` | QA scene: every character in every state, writes `qa/characters_preview*.png`. |

The three character scenes inherit `character_base.tscn` and only override
exported properties, so new variants are a five-line `.tscn` (or just
instance `character_base.tscn` and call `set_colors` / `set_accessories`).

Conventions: 1 unit = 1 m, origin at the feet (y = 0), ~1.8 m tall
(2.1 m with the toque), faces **-Z**. The rig never moves or rotates its own
root except in `face_direction()`, so parent it to your `CharacterBody3D`.

## Instancing

```gdscript
var rig: CharacterRig = preload("res://assets/characters/player.tscn").instantiate()
body.add_child(rig)                     # body is your CharacterBody3D, rig sits at its origin

# a hostile owner recoloured for a specific restaurant
var owner := preload("res://assets/characters/chef_owner.tscn").instantiate() as CharacterRig
owner.set_colors({"shirt": Color.WHITE, "accent": Color("2a6f2a"), "skin": Color("c68642")})
owner.set_accessories({"knife": false, "ski_mask": true})
```

## Animation API

```gdscript
rig.set_state("walk")        # idle | walk | run | attack | hit | eat | dead | stunned
rig.set_move_speed(3.2)      # m/s, scales the walk/run cycle (<= 0 -> per-state default)
rig.face_direction(velocity) # yaw the root toward a world-space direction (XZ only)
rig.get_state()              # current state (also `rig.state`)
```

* `idle`, `walk`, `run`, `eat`, `stunned`, `dead` loop / hold until you change state.
* `attack` and `hit` are **one-shots** (0.4 s / 0.3 s): they play once and return to
  whatever looping state was active before. Calling `set_state("attack")` while
  attacking restarts the swing.
* `dead` falls backwards over 0.7 s and stays down; set any other state to get up.
* `eat` is a seated pose (hips drop ~0.4 m): put the rig at the chair position, not
  on the chair. Hands alternate to the mouth every 0.8 s and the mouth opens/chews.
  Hide held items first if you don't want the chef eating with a knife.
* Every transition cross-fades automatically (no pops).

Signals:

| Signal | When |
|---|---|
| `attack_hit` | impact frame of `attack` (0.2 s in) - apply damage here |
| `state_changed(new_state)` | after every state switch, including automatic returns |
| `one_shot_finished(state)` | `attack` or `hit` finished |

Animation control extras: `auto_advance` (default true; set false and call
`rig.advance(delta)` yourself for deterministic tests/screenshots), `time_scale`.

## Colours and accessories

Exported (editable in the inspector, overridable in inherited scenes, settable at runtime):

| Property | Paints |
|---|---|
| `skin_color` | head, nose, hands, ski-mask eye slot, shins when `long_pants = false` |
| `shirt_color` | chest, upper arms, forearms, hood |
| `pants_color` | pelvis, thighs, shins when `long_pants = true` |
| `hat_color` | cap, toque, headband |
| `accent_color` | shoes, apron |
| `long_pants` | false = shorts (bare shins) |

`set_colors(dict)` accepts any subset of `skin/shirt/pants/hat/accent` (with or
without the `_color` suffix) plus `long_pants`; `get_colors()` returns them all.
Materials are unique per instance, so recolouring one NPC never affects another.

Accessory toggles (bool exports; `set_accessories(dict)` takes keys with or
without the `show_` prefix): `show_chef_hat`, `show_apron`, `show_ski_mask`,
`show_knife`, `show_camera`, `show_cap`, `show_sunglasses`, `show_headband`,
`show_hood`. The ski mask also hides the nose and eyebrows.

Face: `brow_angle` (radians; positive = angry, negative = worried; the chef
uses 0.45) and `brow_height`. The mouth opens automatically in `eat`, `hit`,
`dead`, `stunned` and mid-`attack`.

## Nodes the game may need

All of these have `unique_name_in_owner`, so `rig.get_node("%HandR")` works
from the rig root; full paths are given for clarity.

| Purpose | Path (from rig root) | Helper |
|---|---|---|
| Right-hand attachment (held items) | `Hips/Torso/ArmR/ElbowR/HandR/GripR` | `get_hand_node(true)` |
| Left-hand attachment | `Hips/Torso/ArmL/ElbowL/HandL/GripL` | `get_hand_node(false)` |
| Head pivot (look-at, hats) | `Hips/Torso/Head` | `get_head_node()` |
| Name label / speech bubble anchor (y = 2.05) | `Hips/Torso/Head/LabelAnchor` | `get_label_anchor()` |
| Chest action-cam (+ `RecLight` child) | `Hips/Torso/Camera` | `get_camera_node()` |
| Built-in knife (toggle with `show_knife`) | `.../HandR/GripR/Knife` | |
| Body root (everything that animates) | `Hips` | |

Items parented under a grip should point along the grip's **-Y** (down the
fist); the knife is built that way, so a punch turns into a stab.

## Preview / QA

```
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 assets/characters/preview.tscn
```

Writes `qa/characters_preview.png` (after 1 s of deterministic simulation) and
`qa/characters_preview_2.png` (0.4 s later, to show motion), then quits.
Optional user args after `--`: `--only=<row index>` (0 player, 1 chef, 2 rival)
renders a single character close up at eye height; `--out=<path prefix>`
changes the output files.
