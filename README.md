# LineageOS ROM Build Script

Automated build script for LineageOS

## 🚀 Quick Start

```bash
git clone https://github.com/bijoyv9/build-script.git -b lineage-23.0 build-lineage && cd build-lineage && chmod +x build.sh
./build.sh --device <device_name>
```

## 📋 Prerequisites

**System Requirements:** Ubuntu/Debian Linux, 500GB+ disk space, 16GB+ RAM

**Install Dependencies:**
```bash
# Repo tool
mkdir -p ~/.bin && curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo && chmod a+rx ~/.bin/repo
echo 'export PATH="${HOME}/.bin:${PATH}"' >> ~/.bashrc && source ~/.bashrc

# Build tools
sudo apt update && sudo apt install git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 libncurses5 lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig python3 jq
```

## 🛠️ Usage

### Basic Commands
```bash
./build.sh -d <device_name>              # First build
./build.sh -d <device_name> --skip-sync  # Quick rebuild
./build.sh --help                        # Show all options
```

### Build Options

| Option | Description |
|--------|-------------|
| `--device, -d <name>` | Device to build (required) |
| `--variant <type>` | user/userdebug/eng (default: userdebug) |
| `--skip-sync` | Skip source download |
| `--skip-clone` | Skip device repo cloning |
| `--clean` | Clean build environment |
| `--clean-repos` | Fresh device repositories |

### Common Workflows
```bash
# First build
./build.sh -d <device_name>

# Daily development
./build.sh -d <device_name> --skip-sync

# Production release
./build.sh -d <device_name> --variant user --clean-repos

# Quick test
./build.sh -d <device_name> --skip-sync --skip-clone
```

## 📱 Device Configuration

Device configs are stored in `devices/*.json`. Each JSON defines repositories, branches, and build settings.

### Adding a New Device
1. Copy `devices/device-template.json` to `devices/your-device.json`
2. Update device info, repository URLs, and branches
3. Build: `./build.sh -d your-device`

**Available Devices:**
Check `devices/` directory for configured devices.

---

**Happy Building! 🚀**
