# OCS VR game: phases

The game design plan (`OCSVR_Game_Design_Plan.md` in the team Drive's "OCS VR" folder), split into phases. Each phase is its own branch and pull request, and Aryan merges into `main`.

The team builds the game **one person at a time**, in this order (the build order in the design plan, §0b). A phase is done when its owner posts `From_<Name>_NN_Phase_<n>_Done.md` in the Drive and Aryan merges the PR.

| # | Who | What | Status |
|---|---|---|---|
| 0 | Aryan | Play in the Quest headset: VR grabber, XR rig, OpenXR, Quest plugin and export | Done (in this branch); the Quest playtest is still open |
| **1** | **Aryan** | **Home menu with a placeholder OCS login, plus the menu system the next phases build on: save system, mode picker, Free Play list, Story roadmap shell** | **This branch (`phase-1-menus`)** |
| 2 | Chetan | Two game modes, with placeholder models: Story IRL Act 1 "Set up a pre-built PC" and Free Play "Build your own PC" | Built on `phase-2-modes`; waiting for review and merge |
| 3 | Kashyap | One more mode | Waiting |
| 4 | Ryden | Assigned later | Waiting |
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

## Rules (from the build plan)

- **Every screen is a 3D panel.** Normal screen UI doesn't show in the headset.
- **One input layer:** the menus use one pointer (mouse ray on the laptop, controller ray in the headset).
- **Data, not code:** task text, Free Play cards and the Story roadmap come from `data/`.
- **Saving goes only through `SaveService`,** so OCS saves (phase 5) plug in without touching menus or missions.
- **The headless tests keep passing,** and new logic gets tests.
