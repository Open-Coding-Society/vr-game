# Menu images needed

Every image below has a file name. Save the finished image as **`ui/images/<name>.png`** and the menu picks it up automatically, with no code change (`scripts/ui/menu_theme.gd`, `image()`). Where a file is missing, a named placeholder (`image: <name>`) shows instead.

**For now (interim):** each file in `ui/images/` is one of Google's Material Symbols (Apache 2.0, see `ui/icons/material/LICENSE.md`) drawn in the menu's bronze accent on a cream tile, made by `tools/make_menu_images.gd`. They're flat and match the menus. The real art (team build order, phase 8, Canva) replaces them file by file, using the same names.

**Style for all of them**, so they match the menus:
- **Flat and clean.** Simple shapes, solid colors, crisp edges. **No gradients, no glow, no AI-generated look.**
- **Palette:** the menus are light now. Cream `#EDE6D9`, warm white `#FAF6EE`, white cards `#FFFFFF`, a cream tile `#F3ECDF` behind each image, charcoal `#26231F`, grey `#6B645A`, one accent **bronze `#8C6A3A`**, and green `#2F7D4F` only for "done" ideas.
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
| `task_build_your_own.png` | Free Play: "Build your own PC" | 460 × 300 | A shelf of PC parts in three colors (grey, blue, green) next to an open case. |
| `task_swap_ssd.png` | Free Play: "Swap in an SSD" | 460 × 300 | An open PC case with a screwdriver, an old drive coming out and a new SSD going in. |
| `task_cooler_paste.png` | Free Play: "Reseat the cooler" | 460 × 300 | A CPU with a dot of thermal paste on it, the cooler lifted off beside it. |
| `task_unbox.png` | Free Play: "Unbox the PC" | 460 × 300 | An open box with a PC tower, monitor, keyboard and mouse coming out of it. |
| `task_connect_peripherals.png` | Free Play: "Connect the monitor, keyboard and mouse" | 460 × 300 | The back of a PC tower with an HDMI cable and two USB cables going in. |
| `task_power_on.png` | Free Play: "Plug in power and watch it boot" | 460 × 300 | A power plug going into a wall socket, and a monitor lighting up. |
| `task_go_online.png` | Free Play: "Connect to the network" | 460 × 300 | A network cable from a PC to a small router with a green light. |
| `task_build_network_connect_two.png` | Free Play: "Connect two computers" | 460 × 300 | Two PCs joined by one blue network cable, a green light at each end. |
| `task_build_network_switch.png` | Free Play: "Add a switch" | 460 × 300 | Three PCs, each with a cable to one small white 8-port switch. |
| `task_build_network_router.png` | Free Play: "Add a router" | 460 × 300 | A switch cabled to a blue router, and the router cabled to a wall jack with a globe or cloud. |
| `task_build_network_send_packets.png` | Free Play: "Send data and watch the packets" | 460 × 300 | Small numbered white cubes travelling along a cable from one PC to another, out of order. |
| `task_build_network_interrupt.png` | Free Play: "Interrupt a connection" | 460 × 300 | A cable pulled out of a switch, its light red, with packets stopped before the gap. |
| `task_build_network_redundancy.png` | Free Play: "Add redundancy" | 460 × 300 | Two switches joined by two cables, one of them cut, the PCs still connected. |
| `task_build_network_distribute.png` | Free Play: "Split a workload across machines" | 460 × 300 | Four flat Mac minis, each with a few square tiles of one picture on top. |

The five Phase 2 tasks (`task_build_your_own.png` and the four after it), the seven Build a Network tasks (`task_build_network_*.png`, Phase 3) and Phase 5's tasks (`task_swap_ssd.png`, `task_cooler_paste.png` and the ones listed after them) have no interim icon yet, so their cards show the named placeholder.

**Later:** every new task gets a `task_<mission id>.png` (460 × 300), or the name in its `"image"` field in `data/modules.json`. The menu shows its placeholder until the file is there, so a missing image is easy to spot.
