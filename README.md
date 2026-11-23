# OCS VR: the Godot project

Immersive training for **AP CSP Unit 4** (Computer Systems and Networks), built in **Godot 4.7.2** for the **Meta Quest**: students build a computer, then a network, and each mission's score is saved to the team's Flask backend ([Open-Coding-Society/ocs_backend](https://github.com/Open-Coding-Society/ocs_backend)).

The work follows the team build plan (`OCSVR_Training_Plan.md` section 5 in the team Drive): laptop first, then the Quest.

**New to the project? Start with [SETUP.md](SETUP.md)**: installing Godot, cloning, playing, running the checks, and (optionally) the backend and the progress page.

## Open it

1. Install **Godot 4.7.2 standard** (not .NET). Setup guides with the exact versions are in the team Drive: `OCSVR_Godot_Setup_Windows.md` and `OCSVR_Godot_Setup_macOS.md`.
2. Clone this repo and open `project.godot` from Godot's project manager (**Import**).
3. Press **Play** (F5). Module 1 starts with the "Install the RAM" practice mission, and each finished mission opens the next one after 6 seconds. To play one mission on its own, open its scene and press F6.

## Status

| Build-plan step | State |
|---|---|
| 1. Laptop workbench + one snap task | **Done:** drag the RAM stick into the RAM slot with the mouse |
| 2. One full mission ("Identify components") with hints and a success panel | **Done:** CPU, RAM, SSD and keyboard into their places, checklist and hints on a 3D panel, score/time/attempts on success |
| 4. `TrainingManager` autoload + module registry | **Done:** missions are data in `data/modules.json`; one generic mission script |
| Module 1 missions | **All 5, plus a practice:** Install the RAM (practice), Identify the components, Assemble the system, Execute a task, Add processing capacity, Diagnose a failure |
| 5. Send scores to Flask | **Done:** each finished mission is saved through the training API (sign in, start a session, complete it with retries) |
| OpenXR, Quest export preset, vendors plugin | Being set up by Aryan's side; they get added here |

## How it fits together

| File | Job |
|---|---|
| `scenes/room.tscn` | The room every mission uses: light, floor, table, standing camera, grab layer (`scripts/room.gd`) |
| `scenes/build_computer/identify_components.tscn` | Module 1, mission 1: a motherboard with CPU socket, RAM slot and M.2 slot, a USB spot for the keyboard, the four parts, and the info panel |
| `data/modules.json` | **The module registry**: every module and mission, with its scene, intro and success text, scoring, and each part's and slot's type, name and hint |
| `scripts/module_registry.gd` | Reads and checks the registry; a typo is reported with the field that's wrong |
| `scripts/training_manager.gd` | **The `TrainingManager` autoload**: Intro → Active (first grab starts the clock) → Success; mistakes, score, attempts; emits `module_completed(module_id, score, duration_s)` |
| `scripts/net/score_reporter.gd` | **The `ScoreReporter` autoload**: on `mission_started` it starts a server session; on `module_completed` it completes it with score, time, attempts and device, retrying if the server can't be reached. Practice missions aren't sent |
| `scripts/net/training_api.gd` | The HTTP client for the backend's `/api/authenticate`, `/api/sessions/start`, `/api/sessions/complete` and `/api/learners/<uid>/progress`. Sends the login JWT as `Authorization: Bearer` |
| `scripts/missions/mission.gd` | The one script every mission scene uses: gives the scene's parts and slots their registry data and drives the panel |
| `scripts/ui/info_panel.gd` | A 3D panel (SubViewport on a quad) for intros, checklists, hints and results |
| `scenes/build_computer/assemble_system.tscn` | Module 1, mission 3: mount the motherboard, PSU and SSD in a case, power last |
| `scenes/build_computer/execute_task.tscn` | Module 1, mission 4: carry a photo file from the SSD to RAM, the CPU, then the screen |
| `scenes/build_computer/add_capacity.tscn` | Module 1, mission 5 (advanced): install a GPU, then send step-by-step jobs to the CPU and parallel jobs to the GPU |
| `scenes/build_computer/diagnose_failure.tscn` | Module 1, mission 6 (advanced): read the symptoms, find the broken RAM, then the dead SSD, and swap in spares |
| `scenes/setup_pc/` | Module 2, "Set up a pre-built PC" (Story IRL Act 1): `unbox`, `connect_peripherals`, `power_on` and `go_online`, plus the placeholder shapes in `props/` |
| `scenes/build_pc/build_your_own.tscn` | "Build your own PC": pick a motherboard, CPU, memory, storage, graphics card and power supply from three tiers; it only boots if they work together |
| `scenes/build_pc/parts_shelf.tscn` | The shelf of parts for it: five kinds in three tiers |
| `scenes/parts/cable.tscn` | A cable: a grabbable plug at each end and a wire between them (`scripts/parts/cable.gd`) |
| `scenes/workbench.tscn` | The "Install the RAM" practice mission (step 1's workbench, now registry-only) |
| `scripts/grabbable_part.gd` | A part you can pick up. Knows its `part_type`; on a drop it picks the one slot that judges it (so a keyboard over three slots is one mistake, not three); goes home if not installed |
| `scripts/snap_zone.gd` | A slot (`Area3D`) with a `hint`. It judges a dropped part: right type → installs it and emits `snapped`; wrong type → emits `rejected` |
| `scripts/input/mouse_grabber.gd` | The laptop's grab/drop layer: press, carry, release. The only script that knows about the mouse |
| `data/parts_catalog.json` | The three tiers of each PC part and their specs, read by `scripts/parts/parts_catalog.gd` |
| `scripts/parts/compatibility.gd` | Whether parts work together: one pure function per rule, each returning the message a student reads when it fails |
| `scripts/parts/monitor_screen.gd` | A monitor's picture: plays a mission's boot lines, shows the desktop or a message |
| `scripts/parts/link_light.gd` | A status light that comes on when the slots it watches are filled |
| `scripts/missions/build_pc_mission.gd` | What only Build your own PC does, on top of `mission.gd`: the reason on the monitor, the balanced bonus, the build on the results card |
| `tests/run_tests.gd` | Headless checks (below) |
| `tests/run_mode_tests.gd` | Headless checks for the cables, Set up a pre-built PC and Build your own PC |

The VR rules from the build plan, and where they show up:

1. **Real scale, 1 unit = 1 m.** The RAM stick is 0.133 m long; the table top is 0.9 m high.
2. **Standing player.** The camera is at 1.6 m eye height. Both numbers get replaced by the step 0 headset measurements.
3. **3D, not 2D.** Every part is a 3D object.
4. **UI on 3D panels.** The mission panel is a SubViewport drawn on a quad, tilted toward the player; part names are `Label3D`s. No `CanvasLayer` UI, since it doesn't show in the headset.
5. **One input layer.** Parts and SnapZones only see `grab()` and `drop()`. A controller or hand grabber replaces `MouseGrabber` without touching the game.
6. **No camera moving on its own.** The camera is placed once.
7. **Model setup.** Each part is a body with logic and a simple collision shape, with its model as a child named `Mesh`. The real models live in `models/<part>/`; `tools/fit_models.gd` scales each to real size and writes `models/<part>/<part>_visual.tscn`, which the scenes use. Most models are CC BY 4.0, so **anyone who adds or swaps a model updates [CREDITS.md](CREDITS.md)**.
8. **Origin at the snap point.** The RAM stick's origin is its bottom edge, and each SnapZone has a `SnapPoint` marker.

## Save scores to the backend

The game sends results to the team's Flask backend ([Open-Coding-Society/ocs_backend](https://github.com/Open-Coding-Society/ocs_backend)), and they show up in `GET /api/learners/<uid>/progress` and on the pages site's `/vr/progress/`. Point it at a server and an **activated** account, either with environment variables:

```bash
OCSVR_API_URL=http://localhost:8587 OCSVR_UID=hop OCSVR_PASSWORD=... godot --path .
```

or with a file that stays on your computer, `user://ocsvr_api.cfg` (on a Mac, `~/Library/Application Support/Godot/app_userdata/OCSVR/ocsvr_api.cfg`):

```ini
[api]
base_url="http://localhost:8587"
uid="hop"
password="..."
```

Never commit a password. With no account set up, the game still plays, and the success panel says the score wasn't saved. On the Quest, `adb reverse tcp:8587 tcp:8587` makes the headset's `localhost:8587` reach the laptop's backend.

## Add a mission

1. Make a scene: instance `scenes/room.tscn`, add `InfoPanel` (`scripts/ui/info_panel.gd`), and place your parts (`scripts/grabbable_part.gd`, a `Mesh` child and a collision shape, origin at the snap point) and slots (`scripts/snap_zone.gd`, an `Area3D` with a collision shape and a `SnapPoint` marker).
2. Put `scripts/missions/mission.gd` on the scene's root and set `mission_id` to `module.mission`.
3. Add the mission to `data/modules.json`: its scene, `intro`, `success`, `scoring`, and every part (`type`, `name`) and slot (`accepts`, `name`, `hint`) by node path. Slots can also have:
   - `role`: what the part does, shown when it's installed
   - `requires`: other slots that must be filled first (a part dropped too early is a mistake, and the panel says what comes first)
   - `pass_through: true`: the part is placed here but stays free to move on, so it can go through several stages, like data moving through the computer
   - `capacity`: how many parts fill it (a job queue); they sit side by side along the SnapPoint's x axis
   - `working: true`: a part that isn't broken. It takes nothing (so no `accepts`), isn't on the checklist, and turns any part away with its hint
   - `swappable: true`: a full slot still takes a part of its type, and the part that was in it goes back home. Slots that needed it filled first are emptied too
   - `compat`: a rule in `scripts/parts/compatibility.gd` (`cpu_socket`, `ram_type`, `storage_slot`, `gpu_plug`, `enough_power`, or `power` for both power rules). A part of the right type is also checked against the parts in the slots this one `requires`, and the rule's message is shown when it fails

   A zone with a child node named `Replaced` (the old part's mesh) hides it once the zone is full.

   A mission can also have `"on_complete": "boot"` with `"boot_lines"` (a list of text). When its last slot is filled, the scene's monitor screen (a node named `MonitorScreen` using `scripts/parts/monitor_screen.gd`) shows the lines one after another before the success panel comes up, and the last line stays on the screen. A mission can also give `"monitor"` text for that screen: `start` is shown from the beginning (a PC that is already on) and `linked` once the screen's `link_light` comes on. The first line of each is its heading.

   A mission with `"catalog_parts": true` also uses parts from `data/parts_catalog.json`: a part whose `variant` is a catalog id (`cpu_mid`) takes its type, name, label and tier colour from there and needs no entry under `parts`. `scoring` can have a `balanced_bonus` for missions that give one. The top score should stay at 100: the score API accepts 0 to 100.

   Ready-made pieces for a scene:
   - `scenes/parts/cable.tscn`: a cable with a grabbable plug at each end (`EndA`, `EndB`), listed in the registry like any other part. Set `fixed_end` for a device's own cable (one plug), and `fixed_end_b` as well for a cable that is already plugged in (only its wire).
   - `scripts/parts/link_light.gd`: a light that comes on once the slots in its `zones` are all filled. A monitor screen can watch one through `link_light` and then shows the registry's `monitor.linked` text.
   - `scenes/build_pc/parts_shelf.tscn`: a shelf with a CPU, RAM kit, storage drive, graphics card and power supply in each of the three tiers.

   Missions play in the order they're listed.

No new code is needed. If the registry and the scene disagree (a slot in one but not the other, a slot that accepts a type no part has), the game prints exactly what's wrong when it loads.

## Run the checks

From the repo folder, with `godot` meaning your Godot 4.7.2 binary:

```bash
godot --headless --import
godot --headless --script res://tests/run_tests.gd       # game: snap rules, missions, registry
godot --headless --script res://tests/run_mode_tests.gd  # cables, Set up a pre-built PC, Build your own PC
godot --headless --script res://tests/run_menu_tests.gd  # menus, Free Play, Story roadmap
godot --headless --script res://tests/run_save_tests.gd  # local saves
godot --headless --script res://tests/run_api_tests.gd   # score saving, against a fake server
```

Look for `ALL PASSED` at the end. Godot exits with 0 even if a test script fails to load, so the exit code alone isn't enough.

With the backend running, `tests/run_live_api_test.gd` does one real round trip (set the three `OCSVR_` variables above; without them it prints `SKIPPED`). It creates real sessions for that account.

They check the registry (it loads, and bad data is caught with a clear message), the TrainingManager's states and scoring, the snap rules, and both missions played through the real mouse grabber and camera. For example: a perfect run scores 100 with the right time, wrong drops show the slot's hint and cost points, a big part over several slots counts once, and changing `per_mistake` in the registry changes the score with no code change. Exit code 0 means all passed. A few `ERROR` lines are expected: they come from tests that feed in bad data on purpose.

## Rules for contributing

- Work on a branch and open a pull request into `main`; Aryan merges.
- Keep Godot at **4.7.2** so `project.godot` and the scene files don't churn between versions.
- `.godot/`, `/android/` and `build/` are ignored: every computer makes its own.
