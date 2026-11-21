# Menu images needed

The menus show a named placeholder (`image: <name>`) wherever an image goes. To add one, save it as **`ui/images/<name>.png`**. The menu picks it up automatically, with no code change (`scripts/ui/menu_theme.gd`, `image()`).

**Style for all of them**, so they match the menus:
- **Flat and clean.** Simple shapes, solid colors, crisp edges. **No gradients, no glow, no AI-generated look.**
- **Palette:** near-black `#0E1116` / `#161B22`, card `#1C2330`, white `#F0F3F6`, grey `#9AA4B2`, one accent **OCS blue `#2F81F7`**, and green `#3FB950` only for "done" ideas.
- **No text in the images.** The menu draws titles and descriptions itself.
- **Framing:** the image is cropped to fill its box (corners are rounded by the menu), so keep the subject centered with a little margin.
- **Size:** use the size listed (2× the on-screen size, so it stays sharp in the headset). PNG.

| File name | Where it shows | Size (px) | What it should show |
|---|---|---|---|
| `home_hero.png` | Home screen, right side | 1240 × 1240 | The game in one picture: a PC on one side and a cloud or network on the other, joined in the middle. The title image of the game. |
| `mode_free_play.png` | Mode picker: Free Play card | 860 × 680 | A grid or shelf of separate tasks to choose from, e.g. small cards each with one part (RAM, CPU, cloud). Says "pick anything". |
| `mode_story.png` | Mode picker: Story Mode card | 860 × 680 | A winding path with steps or checkpoints, going from a PC toward a cloud. Says "a journey in order". |
| `mode_open_world.png` | Mode picker: Open World card | 860 × 680 | A desk in a small cube room with a tool rack and parts on shelves. Says "your own space". |
| `story_irl.png` | Story Mode: IRL chapter card | 860 × 680 | Hands-on hardware: an open PC case with parts and a screwdriver. |
| `story_cloud.png` | Story Mode: Cloud chapter card | 860 × 680 | Inside the internet: servers and packets moving along lines between nodes. |
| `story_bridge.png` | Story Mode: Bridge chapter card | 860 × 680 | A PC and a cloud connected by a bridge or cable. |
| `task_install_ram.png` | Free Play: "Install the RAM" | 460 × 300 | A RAM stick going into its slot. |
| `task_identify_components.png` | Free Play: "Identify the components" | 460 × 300 | CPU, RAM, SSD and a monitor or keyboard side by side, as if labelled (no text). |
| `task_assemble_system.png` | Free Play: "Assemble the system" | 460 × 300 | A motherboard with parts being placed in order. |
| `task_execute_task.png` | Free Play: "Execute a task" | 460 × 300 | Data moving from storage, to RAM, to the CPU (arrows or a path). |
| `task_add_capacity.png` | Free Play: "Add processing capacity" | 460 × 300 | A graphics card next to a CPU. GPU vs CPU. |
| `task_diagnose_failure.png` | Free Play: "Diagnose a failure" | 460 × 300 | A part marked as broken (e.g. a red X or a cracked chip) next to a working one. |

**Later:** every new task gets a `task_<mission id>.png` (460 × 300). The menu shows its placeholder until the file is there, so a missing image is easy to spot.
