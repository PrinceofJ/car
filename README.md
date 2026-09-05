# Touge-Game

A PSX-style touge driving game built in **Godot 4**. Arcade drift handling on a procedurally generated mountain pass — hairpins, banked corners, cliff drops, and a hard 384×216 render target to keep the low-fi look honest.

Everything in the world is generated at runtime: the road, the terrain, the guardrails, the warning signs. The engine note and tire squeal are synthesized sample-by-sample rather than played from audio files.

## Controls

| Action | Key |
|---|---|
| Accelerate | `W` / `↑` |
| Brake / reverse | `S` / `↓` |
| Steer | `A` `D` / `←` `→` |
| Handbrake | `Shift` |
| Regenerate touge | `R` |
| Switch to test floor | `T` |
| Dev console | `F1` |

While airborne, the steering and throttle keys pitch and roll the car so you can correct your landing.

## Running it

Open the project folder in Godot 4.4 or newer (it's saved with 4.6 features) and press F5. There are no external dependencies to install.

Blender import is disabled in the project settings, so the `.blend` files in `assets/` are ignored — the game loads the `.obj` versions instead. You don't need Blender installed.

## Handling model

The car is a `CharacterBody3D` with a hand-rolled arcade drift model rather than Godot's `VehicleBody3D`. The core of it is a **traction value** that gets lerped into the velocity each frame:

- **Grip is asymmetric.** Traction drops instantly when you lose it and recovers slowly, so the car snaps loose and eases back.
- **Drift is a state, not a button.** Pulling the handbrake kills lateral grip; once the slip angle passes a threshold at speed, the car enters a drift state that boosts rotation and acceleration. It exits when the car straightens out and the handbrake is released.
- **Throttle can't bank speed during a drift.** `current_speed` is clamped near actual speed while sliding, otherwise the extra throttle would silently accumulate and dump into velocity as a delayed pop when the drift ended.
- **The floor normal is low-pass filtered.** The generated road is faceted, so raw `get_floor_normal()` steps as the car crosses triangle edges. Smoothing it stops the alignment and slope-slip from shaking frame to frame.
- **Slopes actually pull.** On any surface steeper than roughly flat, a slide force gets added along the surface, so hanging off a banked corner costs you.

All of it is exported to the inspector — acceleration, drift entry/exit angles, traction values, air control, coyote time — so it's tunable without touching code.

## Track generation

`touge_generator.gd` builds a downhill mountain pass from a seed:

1. **Centerline.** A heading walks forward while the *turn rate* drifts and damps back toward straight, so curves flow in, hold, and ease out instead of the road snaking randomly each step. Hairpins are injected as 140–165° sweeps with a cooldown, and each one biases opposite to the last so the road switches back rather than spiraling.
2. **Overlap check.** Candidates are rejected if any two distant points come within a minimum distance, and it retries — up to a cap, then falls back to the best attempt.
3. **Smoothing.** Several Chaikin-style subdivision passes round off the polyline.
4. **Banking.** Each cross-section is rolled into the curve based on local signed curvature, capped at a maximum angle. Gravity then helps pull you through corners.
5. **Meshing.** Road surface, painted lines and center dashes, terrain, and signs are each built with `SurfaceTool` and given concave collision. The terrain is deliberately asymmetric: a drivable embankment on one side, a narrow verge and a 70-unit cliff face on the other, steeper than the car's `floor_max_angle` — so going off the wrong side means falling.
6. **Signs.** Corners are flagged by measuring heading change over a lookahead window; warning diamonds get placed a few segments early on the safe side, facing oncoming traffic.

The generator exposes roughly forty parameters in the inspector. `get_spawn_position()` and `get_spawn_direction()` hand the game manager a place to drop the car.

## Presentation

The whole 3D world renders into a **384×216 SubViewport** scaled up 3×, with nearest-neighbor texture filtering — that's where the PSX look comes from, rather than a post-process filter.

`retro_sky.gdshader` is a sky shader with a dusk gradient, a hashed star field with per-star twinkle, and periodic shooting stars that fire on a random schedule.

## Audio

Both sounds are generated procedurally through `AudioStreamGenerator` at 11 kHz, then bit-crushed to match the visuals:

- **Engine** — detuned pulse oscillators with a sub, frequency mapped from speed through a simulated 5-gear box, plus a noise layer.
- **Tire screech** — white noise through a resonant state-variable band-pass filter, center frequency wobbled by an LFO, amplitude driven by the drift state and speed.

## Dev console

Press `F1`. Available commands:

```
fly          toggle a free-flight camera (WASD, mouse look, Space/Shift, Ctrl to sprint)
speed <n>    set fly speed
tp <x y z>   teleport the car or the fly camera
pos          print current position
seed <n>     regenerate the track with a specific seed
regen        regenerate with a random seed
help         list commands
```

There's also an always-on debug overlay in the corner. Any script can push a value to it with `DebugOverlay.watch_property("Name", value)`.

## Project structure

```
scenes/
  Menu.tscn         Play / quit
  GameScene.tscn    SubViewport render pipeline, car, world, console
  DebugOverlay.tscn Autoloaded HUD

scripts/
  car_movement.gd    Drift physics, slope handling, air control
  touge_generator.gd Procedural road, terrain, banking, signs
  camera.gd          Chase cam with speed-based FOV and velocity blending
  engine_sound.gd    Procedural engine synth
  tire_screech.gd    Procedural screech synth
  skid_marks.gd      Runtime skid mesh, capped at a max mark count
  debug_console.gd   In-game console and free-fly camera
  game_manager.gd    Environment switching and car spawn
  debug_overlay.gd   Property watcher HUD

shaders/retro_sky.gdshader   Gradient sky, stars, meteors
assets/                      PSX-style car models by GGBot
godot-neural-network-master/ Vendored ML framework (see below)
```

## Notes

A few things worth knowing if you're picking this up:

- **The neural network framework is vendored but unused.** `godot-neural-network-master/` is a full GDScript/compute-shader ML library, and its `GpuContext` is registered as an autoload, but no game script currently references it. It looks like groundwork for AI drivers. If that's not where this is headed, removing the folder and the autoload would cut a lot of weight.
- **The root `LICENSE` belongs to that library**, not to this project — it's MIT © Sina Majdieh, copied along with the vendored code. The game's own code currently has no license. Worth adding one, and moving the vendored license into its own folder.
- **The action camera is disabled.** `ActionCamController` exists in the scene with a `DriftActionCamera` inside it, but it's set invisible with no update mode and no script driving it.
- Some stray files are committed at the repo root: `project.godot.bak`, loose stock images with hashed filenames, and macOS `.DS_Store` / `._*` files.
- `scenes/GameScene.gdshader` is an empty sky shader stub, unused.

## Credits

- Car models: **PSX Style Cars** by GGBot (August 2023)
- [Godot Neural Network Framework](https://github.com/SinaMajdieh/godot-neural-network) by Sina Majdieh — MIT
