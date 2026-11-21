# OCS VR game: phases

The game design plan (`OCSVR_Game_Design_Plan.md` in the team Drive's "OCS VR" folder), split into phases. Each phase is its own branch and pull request, and Aryan merges into `main`.

The team builds the game **one person at a time**, in this order (the build order in the design plan, §0b). A phase is done when its owner posts `From_<Name>_NN_Phase_<n>_Done.md` in the Drive and Aryan merges the PR.

| # | Who | What | Status |
|---|---|---|---|
| 0 | Aryan | Play in the Quest headset: VR grabber, XR rig, OpenXR, Quest plugin and export | Done (in this branch); the Quest playtest is still open |
| **1** | **Aryan** | **Home menu with a placeholder OCS login, plus the menu system the next phases build on: save system, mode picker, Free Play list, Story roadmap shell** | **This branch (`phase-1-menus`)** |
| 2 | Chetan | Two game modes, with placeholder models | Next |
| 3 | Kashyap | One more mode | Waiting |
| 4 | Ryden | Assigned later | Waiting |
| 5 | Aaditya | Finish the game | Waiting |
| 6 | Chetan + one more Claude | Bug fixes | Waiting |
| 7 | Aryan | Detailed, dissectible 3D models | Waiting |
| 8 | Aarav / Jake | Canva menu art: the images in `docs/IMAGES_NEEDED.md` | Waiting |
| 9 | Team | VR test | Waiting |
| 10 | Team | Flask saving (`OCSSaveBackend` plus real login) | Waiting |

**For Phase 2 and later:**
- **New task screens:** add them as menu pages in `scripts/menus/menu.gd` using `menu_theme.gd`'s pieces.
- **New tasks:** add entries to `data/modules.json` (Free Play) and `data/story.json` (Story roadmap).
- **Saving:** save through `SaveService` only.

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
