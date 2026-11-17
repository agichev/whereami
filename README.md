# Where am I?

A realistic PSX / Found Footage Backrooms psychological survival horror game built with **Godot Engine 4 (Forward+)**.

- **Developer Page**: [https://devdown.itch.io/](https://devdown.itch.io/)

---

## Prerequisites

- [Godot Engine **4.7.x**](https://godotengine.org/download) (Standard edition, Forward+ rendering support). **Tested with 4.7.2.**
  Godot 4.3 and older will **not** run this project: `project.godot` declares 4.7 features and the scripts use APIs added after 4.3.
- Godot Export Templates matching your Godot version (only needed for standalone binaries / `.pck` builds)

---

## Quick Start (Running from Source)

Clone the repository:
```bash
git clone https://github.com/agichev/whereami.git
cd whereami
```

### Step 1 — Import assets (required once after cloning)

The repository stores the **source** assets (`.png`, `.fbx`, `.glb`, `.mp3`, …) together with their `.import`
metadata. The imported cache lives in `.godot/` and is **not** versioned, so a fresh clone has nothing to load yet.

```bash
godot --headless --path . --import
```

Nothing is printed on success — this command opens the editor headless, imports every asset and quits.
You can skip it if you open the project in the editor first and wait for the import progress bar to finish.

> Skipping this step is the reason for errors like
> `Failed loading resource: res://.godot/imported/kane_wallpaper.png-….ctex. Make sure resources have been imported by opening the project in the editor at least once.`
> and a black screen with a broken player model.

### Step 2 — Run the game

```bash
godot --path .
```

### One-command shortcut

`run.sh` (Linux/macOS) and `run.bat` (Windows) do both steps: import, then launch.
They use `godot` from `PATH`, or a `godot`/`godot.exe` binary placed next to `project.godot`
(that local binary is git-ignored), or `$GODOT_BIN` / `%GODOT_BIN%` if you set it.

### Running via GUI Editor
1. Open **Godot Engine**, click **Import**, select `project.godot` inside this directory, and click **Import & Edit**.
2. Wait until the import progress bar in the bottom bar disappears (first launch only).
3. Press <kbd>F5</kbd> (or the **Play** button in the top-right corner).

---

## Linux Instructions

### 1. Install Runtime & Driver Dependencies

#### Ubuntu / Debian / Linux Mint:
```bash
sudo apt update
sudo apt install -y git wget unzip libvulkan1 libgl1-mesa-dri libx11-6 \
    libxcursor1 libxinerama1 libxrandr2 libxi6 libasound2
```

#### Arch Linux / Manjaro:
```bash
sudo pacman -S --needed git wget unzip vulkan-driver mesa libx11 libxcursor \
    libxinerama libxrandr libxi alsa-lib
```

#### Fedora / RHEL:
```bash
sudo dnf install -y git wget unzip vulkan-loader mesa-dri-drivers libX11 \
    libXcursor libXinerama libXrandr libXi alsa-lib
```

### 2. Download Godot Binary (if not installed)

```bash
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip
chmod +x Godot_v4.7.2-stable_linux.x86_64
sudo mv Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot
```

### 3. Import and Run

```bash
godot --headless --path . --import
godot --path .
```

### 4. Build & Export for Linux

#### Option A: Export Standalone Linux Binary (requires export templates)
```bash
mkdir -p build
godot --headless --path . --export-release "Linux x86_64" build/WhereAmI.x86_64
chmod +x build/WhereAmI.x86_64
./build/WhereAmI.x86_64
```

#### Option B: Export Resource Pack (`.pck`) and Run with Godot Runner
```bash
mkdir -p build
godot --headless --path . --export-pack "Linux x86_64" build/WhereAmI.pck
godot --main-pack build/WhereAmI.pck
```

---

## Windows Instructions

### Via Command Line (Headless Export):
```cmd
mkdir build
godot --headless --path . --export-release "Windows x86_64" build\WhereAmI.exe
```

Available presets in `export_presets.cfg`: `Windows x86_64`, `Windows x86_32`, `Linux x86_64`, `Linux x86_32`.

---

## Controls

- <kbd>W</kbd> <kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd> — Move
- <kbd>Shift</kbd> — Sprint
- <kbd>Mouse</kbd> — Look around (handheld camcorder motion)
- <kbd>Mouse Wheel Up / Down</kbd> — Camcorder optical zoom in / out
- <kbd>E</kbd> — Interact with doors
- <kbd>F</kbd> — Toggle flashlight
- <kbd>Esc</kbd> — Pause menu / Settings

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `Failed loading resource: res://.godot/imported/...` | Assets were never imported. Run `godot --headless --path . --import` (Step 1). |
| `Parse Error: Static function "load_from_file()" not found` | You are running Godot **4.3 or older**. Use Godot 4.7.x. |
| `Parse Error: Could not preload resource file "res://audio/..."` | Same as the first row: the audio resources are not imported yet. |
| Black screen, only text/UI visible, no character | Missing import (Step 1); verify that `.godot/imported/` was created next to `project.godot`. |
| Export fails with `Could not find template` | Install export templates for your exact Godot version (Editor → Manage Export Templates). |

Import errors about `res://doors/TextureLowPoly.png` are harmless: the door FBX files reference a texture
that is not shipped in the repository, so the door leaf gets its material assigned in code
(`interactive_door.gd`).

---

## License

See [LICENSE](LICENSE) for details.
