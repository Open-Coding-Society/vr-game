# OCS VR game: phases

The game design plan (`OCSVR_Game_Design_Plan.md` in the team Drive's "OCS VR" folder) split into phases. Each phase is its own branch and pull request. Aryan merges into `main`.

| Phase | What | Status |
|---|---|---|
| 0 | Play in the Quest headset: VR grabber, XR rig, OpenXR, Quest plugin and export (build-plan step 3) | Done on `quest-vr`; the Quest playtest is still open |
| **1** | **Menus: save system, Home screen, Login placeholder, mode picker, Free Play, Story roadmap shell** | **This branch (`phase-1-menus`)** |
| 2 | Tools: `Tool`, `ToolZone`, the tool rack; existing missions turned into tool-based tasks | Not started |
| 3 | Story IRL, Acts 1–2 (set up a pre-built PC, inside the PC), with the roadmap unlocking as you go | Not started |
| 4 | Cloud world and Story Cloud, Acts 1–2 (needs Mr. Mortensen's OK for the wider scope) | Not started |
| 5 | OCS saves: `OCSSaveBackend` plus the Flask `VRProfile` API (OCS pattern), and real login | Not started |
| 6 | Open World: desk, cube room, spawn menu, racks, Transfer to Cloud | Not started |
| 7 | Story IRL Acts 3–4, Cloud Acts 3–9, Bridge modules | Not started |
| Art | Detailed 3D models, plus the menu images listed in `docs/IMAGES_NEEDED.md` | Alongside every phase (Aryan) |

## Phase 1 steps (one commit each)

| # | Step | Checked by |
|---|---|---|
| 1 | Fix current bugs: project icon (Quest export error) | Clean import; `run_tests.gd` and `run_api_tests.gd` pass |
| 2 | This file: the phase split | n/a |
| 3 | `SaveService` autoload with local saves (`user://ocsvr_save.json`): one versioned save shape, results recorded automatically when a mission ends | `tests/run_save_tests.gd` |
| 4 | Menu UI kit: flat dark theme with the OCS blue accent (rounded, thin borders, no gradients), a 3D menu screen that shows normal Godot UI, and one pointer for mouse and controllers | `tests/run_menu_tests.gd` |
| 5 | Menu scene and Home screen: Log in (placeholder) or Play locally, then the mode picker (Free Play, Story Mode, Open World). It becomes the game's first scene. | `run_menu_tests.gd` |
| 6 | Free Play: Computer and Cloud tabs and scrollable task cards from `data/modules.json` (title, description, topic, difficulty, ✔ and best score). Start any task; it returns to Free Play when done. | `run_menu_tests.gd`, `run_tests.gd` |
| 7 | Story Mode shell: pick the IRL or Cloud chapter, then a roadmap of acts and tasks from `data/story.json` (done, next, locked). Existing missions are playable from it; the rest are marked planned. | `run_menu_tests.gd` |
| 8 | `docs/IMAGES_NEEDED.md`: every menu image with its size and a short description. Placeholders show until the real images are added. | n/a |

## Rules (from the build plan)

- **Every screen is a 3D panel.** Normal screen UI doesn't show in the headset.
- **One input layer:** the menus use one pointer (mouse ray on the laptop, controller ray in the headset).
- **Data, not code:** task text, Free Play cards and the Story roadmap come from `data/`.
- **Saving goes only through `SaveService`,** so OCS saves (phase 5) plug in without touching menus or missions.
- **The headless tests keep passing,** and new logic gets tests.
