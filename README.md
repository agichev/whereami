# Where am I?

A realistic PSX / Found Footage Backrooms psychological survival horror game built with **Godot Engine 4 (Forward+)**.

- **Developer Page**: [https://devdown.itch.io/](https://devdown.itch.io/)

---

## Prerequisites

- [Godot Engine 4.3+](https://godotengine.org/download) (Standard or .NET edition, Forward+ rendering support)
- Godot Export Templates matching your Godot version (if building standalone binaries)

---

## Running from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/agichev/whereami.git
   cd whereami
   ```
2. Open **Godot Engine**, click **Import**, select `project.godot` inside this directory, and click **Import & Edit**.
3. Press <kbd>F5</kbd> (or the **Play** button in the top-right corner) to run the game directly in the editor.

---

## Building / Exporting Standalone Binaries

### Option 1: Via Godot Editor (GUI)

1. In Godot, navigate to **Project** -> **Export...**.
2. Select your target preset:
   - **Windows Desktop** (`WhereAmI.exe`)
   - **Linux/X11** (`WhereAmI.x86_64`)
3. Click **Export Project...**, choose an output folder, and export.

### Option 2: Via Command Line (Headless)

Make sure Godot is in your system `PATH`:

#### Windows:
```bash
godot --headless --export-release "Windows Desktop" build/WhereAmI.exe
```

#### Linux:
```bash
godot --headless --export-release "Linux/X11" build/WhereAmI.x86_64
```

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

## License

See [LICENSE](LICENSE) for details.
