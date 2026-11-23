# OCS VR: set it up on your computer

Everything a teammate needs to get the game (and, if you want, the backend and the progress page) running on their own Mac or Windows PC. Part A is all you need to play and work on the game; B and C are optional.

| Part | What you get | Time |
|---|---|---|
| **A. The game** | All six Build a Computer missions, playable with the mouse | ~15 min |
| B. The backend | Mission scores saved to your own local Flask server | ~15 min |
| C. The progress page | The pages site's `/vr/progress/` page showing those scores | ~20 min |
| D. Building for the Quest | The Android/Quest tools | Follow the team Drive guide |


---

## A. The game

### 1. Install Godot 4.7.2 (standard, not .NET)

Everyone uses exactly this version, so the project files don't change between computers.

| Your computer | Download | Install |
|---|---|---|
| Mac (Apple Silicon or Intel) | [Godot_v4.7.2-stable_macos.universal.zip](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_macos.universal.zip) | Unzip and drag **Godot.app** into **Applications**. It's signed and notarized, so it should just open; if macOS blocks it, right-click → **Open**. |
| Windows | [Godot_v4.7.2-stable_win64.exe.zip](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip) | Unzip to a folder that isn't synced by OneDrive (e.g. `C:\Godot`). Use the **x64** build, even on a Windows-on-ARM laptop: the Quest plugin has no ARM build. |

You don't need the export templates, Java or the Android SDK to play on the laptop; those are only for building the Quest app (part D).

### 2. Get the project

You need [Git](https://git-scm.com/downloads) and access to the team's repos in the Open Coding Society GitHub org (ask Yash or Aryan). Clone it somewhere **not** synced by iCloud or OneDrive:

```bash
git clone https://github.com/Open-Coding-Society/vr-game.git
cd vr-game
```

### 3. Open and play

1. Open Godot. In the Project Manager click **Import**, pick `vr-game/project.godot`, then **Import & Edit**. The first open takes a minute while Godot builds its `.godot/` cache.
2. Press **F5** (or the ▶ Play button, top right).
3. The "Install the RAM" practice opens. **Press on a part, drag it, and let go** over where it belongs. Each mission opens the next one about 6 seconds after you finish, through all six.

To play one mission on its own, open its scene in `scenes/build_computer/` and press **F6**.

### 4. Run the checks (before you push anything)

From the `vr-game` folder. On a Mac, Godot's command-line program is inside the app; on Windows, use the `.exe` you unzipped.

```bash
# Mac
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --headless --import
$GODOT --headless --script res://tests/run_tests.gd
$GODOT --headless --script res://tests/run_mode_tests.gd
$GODOT --headless --script res://tests/run_menu_tests.gd
$GODOT --headless --script res://tests/run_save_tests.gd
$GODOT --headless --script res://tests/run_api_tests.gd
```

```powershell
# Windows (PowerShell)
$GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $GODOT --headless --import
& $GODOT --headless --script res://tests/run_tests.gd
& $GODOT --headless --script res://tests/run_mode_tests.gd
& $GODOT --headless --script res://tests/run_menu_tests.gd
& $GODOT --headless --script res://tests/run_save_tests.gd
& $GODOT --headless --script res://tests/run_api_tests.gd
```

Each one should end with **`ALL PASSED`** (90, 208, 89, 21 and 21 checks today). Read that line, not just the exit code: Godot exits with 0 even when a test script fails to load. A few `ERROR` lines are expected; they come from tests that feed in bad data on purpose.

### 5. Working on it

- Make a branch, commit, push, and open a pull request; Aryan merges. Don't push to `main`.
- Commit as yourself and add `Co-authored-by: Phantom-deploy <154046285+Phantom-deploy@users.noreply.github.com>` for team work.
- New missions are data: see "Add a mission" in the [README](README.md).

---

## B. Save scores to your own backend (optional)

The game saves each finished mission through the training API in [Open-Coding-Society/ocs_backend](https://github.com/Open-Coding-Society/ocs_backend). To see that on your computer, run the backend locally. You need Python 3.10 or newer (on Windows, do this part in WSL Ubuntu).

```bash
git clone https://github.com/Open-Coding-Society/ocs_backend.git
cd ocs_backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Make a file named `.env` in that folder (it's ignored by git; never commit it). These are the example test accounts from the OCS README:

```ini
ADMIN_USER='Thomas Edison'
ADMIN_UID='toby'
ADMIN_PASSWORD='123Toby!'
TEACHER_USER='Nikola Tesla'
TEACHER_UID='niko'
TEACHER_PASSWORD='123Niko!'
USER_NAME='Grace Hopper'
USER_UID='hop'
USER_PASSWORD='123Grace!'
DEFAULT_PASSWORD='123Qwerty!'
IS_PRODUCTION=false
SECRET_KEY='any-long-random-text'
```

Then build the database **once** and start the server:

```bash
python scripts/db_init.py      # first time only: it wipes and reseeds the database
python main.py                 # serves http://localhost:8587
```

If you already had this backend running before the training API was merged, don't run `db_init.py` again; run `python scripts/db_upgrade.py` instead, which adds the new table and keeps your data.

**Point the game at it.** Either start Godot with these set:

```bash
OCSVR_API_URL=http://localhost:8587 OCSVR_UID=hop OCSVR_PASSWORD='123Grace!' /Applications/Godot.app/Contents/MacOS/Godot --path .
```

or make a settings file Godot reads on its own: `ocsvr_api.cfg` in Godot's user folder for this project (Mac: `~/Library/Application Support/Godot/app_userdata/OCSVR/`; Windows: `%APPDATA%\Godot\app_userdata\OCSVR\`):

```ini
[api]
base_url="http://localhost:8587"
uid="hop"
password="123Grace!"
```

Finish a mission (not the practice one): the success panel ends with **"Score saved to hop's progress."** To check from the command line, with the backend running:

```bash
OCSVR_API_URL=http://localhost:8587 OCSVR_UID=hop OCSVR_PASSWORD='123Grace!' $GODOT --headless --script res://tests/run_live_api_test.gd
```

It should end with `ALL PASSED` (it adds a real session for `hop`).

---

## C. The progress page on the pages site (optional)

The page is in pull request [Open-Coding-Society/ocs_frontend#1](https://github.com/Open-Coding-Society/ocs_frontend/pull/1), branch `vr-progress-page`. It needs the backend from part B running, plus Ruby, Bundler and Python (the [OCS pages README](https://github.com/Open-Coding-Society/ocs_frontend#readme) covers installing them).

```bash
git clone https://github.com/Open-Coding-Society/ocs_frontend.git
cd ocs_frontend
git switch vr-progress-page
python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
bundle install
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
make dev systems/vr-training
```

Then open http://localhost:4500/vr/progress/, sign in as `hop` (or `niko`, the teacher, who can look up any learner), and click **Continue anyway** past the Spring warning.

Two gotchas from testing this:

- The pages build fails if the folder's path contains a **space** (e.g. `Application Support`). Clone it somewhere like `~/code/ocs_frontend`.
- Without the `LANG` line, Ruby Sass stops on a text-encoding error.

---

## D. Building for the Quest

Building the Android app needs the export templates, Java 17, the Android SDK and a debug keystore. Follow the team Drive guide for your computer (`OCS VR/OCSVR_Godot_Setup_macOS.md` or `OCSVR_Godot_Setup_Windows.md`); the Mac one was tested on Nov 18. The OpenXR settings, the Quest plugin and the "Quest" export preset are being added to this repo by Aryan's side.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| Godot says the project is from another version | You have the wrong Godot. Use 4.7.2 standard. |
| The game opens but nothing happens when you press a part | Press directly on the part (the label floats above it), hold, drag, then let go. |
| Panel says "Score not saved: no account is set up" | Expected without part B. With part B, check the settings file or variables, and that the backend is running. |
| "Score not saved. Sign-in failed (HTTP 401)" | Wrong `uid` or password, or the account isn't activated. The seeded `hop` account works. |
| "Can't reach the server" | The backend isn't running, or `base_url` is wrong. |
| Tests print `SCRIPT ERROR` and no `ALL PASSED` | Run `--headless --import` first (after pulling new files), then run the tests again. |
