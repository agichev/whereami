# Where am I?

A realistic PSX / Found Footage Backrooms psychological survival horror game built with **Godot Engine 4 (Forward+)**.

- **Developer Page**: [https://devdown.itch.io/](https://devdown.itch.io/)

---

## Prerequisites

- [Godot Engine 4.3+](https://godotengine.org/download) (Standard or .NET edition, Forward+ rendering support)
- Godot Export Templates matching your Godot version (if exporting standalone binaries)

---

## Quick Start (Running from Source)

Clone the repository:
```bash
git clone https://github.com/agichev/whereami.git
cd whereami
```

### Running via GUI Editor
1. Open **Godot Engine**, click **Import**, select `project.godot` inside this directory, and click **Import & Edit**.
2. Press <kbd>F5</kbd> (or the **Play** button in the top-right corner).

### Running directly via CLI
You can launch the game without opening the editor:
```bash
godot --path .
```

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
wget https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip Godot_v4.3-stable_linux.x86_64.zip
chmod +x Godot_v4.3-stable_linux.x86_64
sudo mv Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot
```

### 3. Build & Export for Linux

#### Option A: Export Standalone Linux Binary (requires export templates)
```bash
mkdir -p build
godot --headless --export-release "Linux" build/WhereAmI.x86_64
chmod +x build/WhereAmI.x86_64
./build/WhereAmI.x86_64
```

#### Option B: Export Resource Pack (`.pck`) and Run with Godot Runner
```bash
mkdir -p build
godot --headless --export-pack "Linux" build/WhereAmI.pck
godot --main-pack build/WhereAmI.pck
```

---

## Windows Instructions

### Via Command Line (Headless Export):
```cmd
mkdir build
godot --headless --export-release "Windows Desktop" build\WhereAmI.exe
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
