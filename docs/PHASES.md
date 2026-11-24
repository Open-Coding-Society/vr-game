# OCS VR game: phases

The game design plan (`OCSVR_Game_Design_Plan.md` in the team Drive's "OCS VR" folder), split into phases. Each phase is its own branch and pull request, and Aryan merges into `main`.

The team builds the game **one person at a time**, in this order (the build order in the design plan, §0b). A phase is done when its owner posts `From_<Name>_NN_Phase_<n>_Done.md` in the Drive and Aryan merges the PR.

| # | Who | What | Status |
|---|---|---|---|
| 0 | Aryan | Play in the Quest headset: VR grabber, XR rig, OpenXR, Quest plugin and export | Done; the Quest playtest is still open |
| 1 | Aryan | Home menu with a placeholder OCS login, plus the menu system the next phases build on: save system, mode picker, Free Play list, Story roadmap shell | Done; merged into `main` |
| 2 | Chetan | Two game modes, with placeholder models: Story IRL Act 1 "Set up a pre-built PC" and Free Play "Build your own PC" | Done; merged into `main` |
| 3 | Kashyap | One more mode: "Build a Network", played as Story IRL Act 4 "Small rigs" and listed in Free Play | Done; merged into `main` |
| 4 | Ryden | Assigned later | Next |
| 5 | Aaditya | Finish the game | Waiting |
| 6 | Chetan + one more Claude | Bug fixes | Waiting |
| 7 | Aryan | Detailed, dissectible 3D models | Waiting |
| 8 | Aarav / Jake | Canva menu art: the images in `docs/IMAGES_NEEDED.md` | Waiting |
| 9 | Team | VR test | Waiting |
| 10 | Team | Flask saving (`OCSSaveBackend` plus real login) | Waiting |

**For Phase 2 and later:**
- **The menus' look** is in `scripts/ui/menu_theme.gd`: every color and size is a constant there. Change the look there, not in a page. `tests/run_menu_tests.gd` checks that each kind of text still stands out from its background.
- **New task screens:** add them as menu pages in `scripts/menus/menu.gd` using `menu_theme.gd`'s pieces.
- **New tasks:** add entries to `data/modules.json` (Free Play) and `data/story.json` (Story roadmap).
- **Saving:** save through `SaveService` only.

## Phase 1 steps (one commit each)

| # | Step | Checked by |
|---|---|---|
| 1 | Fix current bugs: project icon (Quest export error) | Clean import; `run_tests.gd` and `run_api_tests.gd` pass |
| 2 | This file: the phase split | n/a |
| 3 | `SaveService` autoload with local saves (`user://ocsvr_save.json`): one versioned save shape, results recorded automatically when a mission ends | `tests/run_save_tests.gd` |
| 4 | Menu UI kit: flat theme (rounded, thin borders, no gradients; dark with an OCS blue accent at first, changed to white and cream with a bronze accent in Phase 2), a 3D menu screen that shows normal Godot UI, and one pointer for mouse and controllers | `tests/run_menu_tests.gd` |
| 5 | Menu scene and Home screen: Log in (placeholder) or Play locally, then the mode picker (Free Play, Story Mode, Open World). It becomes the game's first scene. | `run_menu_tests.gd` |
| 6 | Free Play: Computer and Cloud tabs and scrollable task cards from `data/modules.json` (title, description, topic, difficulty, ✔ and best score). Start any task; it returns to Free Play when done. | `run_menu_tests.gd`, `run_tests.gd` |
| 7 | Story Mode shell: pick the IRL or Cloud chapter, then a roadmap of acts and tasks from `data/story.json` (done, next, locked). Existing missions are playable from it; the rest are marked planned. | `run_menu_tests.gd` |
| 8 | `docs/IMAGES_NEEDED.md`: every menu image with its size and a short description. Placeholders show until the real images are added. | n/a |

## Phase 2 steps

From `OCSVR_Phase2_Plan.md` in the team Drive. New checks are in `tests/run_mode_tests.gd` unless another file is named.

| # | Step | Checked by |
|---|---|---|
| 1 | Two-ended cables: `scenes/parts/cable.tscn` and `scripts/parts/cable.gd` | A plug fits a port of its type only; `requires` sets the order |
| 2 | "Set up a pre-built PC" missions 1 and 2: unbox the PC, connect the monitor, keyboard and mouse | Full runs through the mouse; wrong spots and wrong ports are turned away |
| 3 | Missions 3 and 4: plug in power and watch it boot (`monitor_screen.gd`, `on_complete` and `boot_lines` in the registry), connect to the network (`link_light.gd`) | The wall socket is blocked until both devices have their cable; the boot lines play in order; the link light needs both ends |
| 4 | Story IRL Act 1 plays the four missions | `run_menu_tests.gd`: the act's tasks unlock in order |
| 5 | `data/parts_catalog.json` and `scripts/parts/compatibility.gd` | Every rule passes and fails with its message, with no scene |
| 6 | `scenes/build_pc/parts_shelf.tscn` and `variant` on `GrabbablePart` | Each shelf part loads its specs, label and tier colour |
| 7 | "Build your own PC": the scene, `compat` and `swappable` slots, the power button, the balanced bonus and the results card | Matching builds boot; each mismatch shows its message; parts can be swapped |
| 8 | Free Play and Story Act 3 play it | `run_menu_tests.gd`: the card is listed and launches; `tools/e2e_menu_flow.gd` plays both modes |

Where Phase 2 differs from its plan:
- **Score:** Build your own PC gives 90 for a PC that works and 10 more for a balanced build, so the top score is 100. The plan said "+10" on top of 100, but the score API accepts 0 to 100.
- **Memory:** the catalog's RAM entries are kits of two sticks, so one kit fills the memory slots.
- **Link light:** it comes on when both ends of the network cable are in, not the router end alone.
- **Wall socket:** it is a power strip on the desk, since the room's wall is out of reach.
- **Power cable ends:** the plan's one `power` plug type is two here, `power_plug` for the end that goes into a device and `wall_plug` for the other, so the ends can't be mixed up. The monitor has its own power slot, `Monitor/PowerIn`.
- **Storage rule:** all three motherboards in the catalog have an M.2 slot, so "This board has no M.2 slot for that drive." can't come up in play yet. The rule is written and tested for the day a board without one is added.
- **Free Play order:** the new tasks are listed after the six that were there, so the list's first task is unchanged.
- **Commits:** steps 1 to 6 are one commit each. From step 7 on there is one commit per change, and so for the fixes after review.

## Phase 3 steps

From `OCSVR_Phase3_Plan.md` in the team Drive. Mr. Mortensen's second module, Build a Network, in seven missions: connect two computers, add a switch, add a router, send data and watch the packets, interrupt a connection, add redundancy, split a workload across machines. New checks are in `tests/run_network_tests.gd` unless another file is named.

| # | Step | Checked by |
|---|---|---|
| 1 | `scripts/network/network_graph.gd`: the network as data (devices, cables, paths, single points of failure) | Paths, disconnects, PCs not forwarding, `bridges()` on a line, a ring and a star, `survives_any_single_cut` |
| 2 | Removable slots (`"removable"`, the `removed` signal) and the cable's `plugged` and `unplugged` signals; the link light goes dark when a cable comes out | A removable part can be pulled out and plugged in again; a fixed one can't; removing isn't a mistake |
| 3 | `scripts/network/network_device.gd` and the placeholder devices in `scenes/network/devices/` (PC, Mac mini, GS108 switch, GL.iNet router, server, Internet wall jack), plus a blue Cat6 cable | Each device's ports load as `ethernet` SnapZones with the right names and lights |
| 4 | `scripts/missions/network_mission.gd`, the `goal` field and `optional` slots in `mission.gd` | Each goal kind passes and fails; old missions still finish the old way |
| 5 | Missions 1 to 3 (connect two, switch, router) and their registry entries | Each finishes when its goal is met, through the mouse; WAN and LAN swapped is turned away |
| 6 | `scripts/network/packet_flow.gd` and mission 4 (send packets) | Packets follow `path()` along the cables, arrive out of order and are put back in order; never more than 20 at once |
| 7 | Missions 5 and 6 (interrupt, redundancy) | Packets stop on a cut and carry on once it's restored; the redundancy check really cuts each link; a ring passes and a line fails |
| 8 | `scripts/network/job_board.gd` and mission 7 (distribute) | The time and speedup sums; a mini that isn't on the network turns work away; the even-spread bonus |
| 9 | Story IRL Act 4, Free Play, `docs/IMAGES_NEEDED.md` and this file | `run_menu_tests.gd`: Act 4's missions are listed, launch, and unlock in order |

Where Phase 3 differs from its plan:
- **Redundancy check:** a PC's only cable isn't one of the cuts the game tests. A computer with one network port can't have a second path, so with the plan's goal (all four PCs) no network could pass. The check cuts every other link, so the second path the player adds is between the switches.
- **Job slots** take 4 tiles, not 3. With 3, the 12 tiles would always be spread 3-3-3-3 over all four minis, so "at least 3 machines" and the even-spread bonus would mean nothing. With 4, a player can use three machines (4-4-4, 4.5 s) or all four (3-3-3-3, 3.5 s and the bonus).
- **Time bar sum:** the plan's rule says 0.5 s of network time per machine, but its example ("Parallel: 3.5 s" for 12 tiles on 4 machines) has 0.5 s in all. The game follows the example: each machine is sent its work at the same time, so the job takes the busiest machine's tiles x 1 s, plus 0.5 s.
- **Distribute score:** 90 for finishing and 10 more for an even spread, as Build your own PC does, since the score API takes 0 to 100.
- **A mini that isn't on the network** turns a tile away with its hint, but that isn't counted as a mistake: mistakes are wrong plugs. It works through a new, generic slot `gate`.
- **WAN and LAN:** the internet cable's plugs are their own type (`wan`), taken only by the router's WAN port and the wall jack, so WAN and LAN swapped is turned away like any wrong plug.
- **Ports** are on the top of each placeholder device, so they can be reached from above and seen from the laptop camera. Everything fits on the room's 1.2 m desk, so no longer table was needed.
- **Interrupt:** plugging the marked cable back into a different switch port also counts as restoring it.
- **Cables that start plugged in** (`start_ports` on a cable) are how missions 3 to 7 start with a network already cabled.
- **Free Play images:** a mission can name its card's image (`"image"` in `data/modules.json`), so these seven are `task_build_network_<id>.png` as the plan asks.
- **Story Act 4:** the two tasks still planned are `irl.rigs.server_rack` and `irl.rigs.pi_cluster`. The old planned ids for the five network tasks are gone, since those tasks are now the missions themselves; saves only ever point at playable tasks.
- **Not done here:** no IP addresses (mission 3) and no packet scanner; both are questions for Aryan in the plan.
- **Commits:** one per step.

## Rules (from the build plan)

- **Every screen is a 3D panel.** Normal screen UI doesn't show in the headset.
- **One input layer:** the menus use one pointer (mouse ray on the laptop, controller ray in the headset).
- **Data, not code:** task text, Free Play cards and the Story roadmap come from `data/`.
- **Saving goes only through `SaveService`,** so OCS saves (phase 5) plug in without touching menus or missions.
- **The headless tests keep passing,** and new logic gets tests.
