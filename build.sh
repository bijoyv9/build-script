#!/bin/bash

# Universal build script for LineageOS
# Author: bijoyv9

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ROM_NAME="LineageOS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$HOME/lineage"
MANIFEST_URL="https://github.com/SM8250-Common/android.git"
MANIFEST_BRANCH="lineage-23.0"
SYNC_JOBS="24"

# Device configuration file (will be loaded from JSON)
DEVICE_CONFIG_FILE=""
DEVICE=""

# Build configuration - will be overridden by JSON or command line args
BUILD_VARIANT="userdebug"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "Command '$1' not found. Please install it first."
        exit 1
    fi
}

# Function to load device configuration from JSON
load_device_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        print_error "Device configuration file not found: $config_file"
        exit 1
    fi

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it: sudo apt-get install jq"
        exit 1
    fi

    print_status "Loading device configuration from $config_file"

    # Export device configuration as global variables
    DEVICE=$(jq -r '.device.codename' "$config_file")
    DEVICE_FULL_NAME=$(jq -r '.device.full_name' "$config_file")
    DEVICE_MANUFACTURER=$(jq -r '.device.manufacturer' "$config_file")

    # Override build config from JSON if not set by command line
    if [ -z "$BUILD_VARIANT_OVERRIDE" ]; then
        BUILD_VARIANT=$(jq -r '.build.variant // "userdebug"' "$config_file")
    fi

    print_success "Device configuration loaded: $DEVICE ($DEVICE_FULL_NAME)"
}

# Function to get repository list from JSON
get_repositories() {
    local config_file="$1"
    jq -r '.repositories | to_entries[] | .key' "$config_file"
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check for required tools
    check_command "repo"
    check_command "git"
    check_command "python3"
    check_command "make"
    check_command "gcc"
    
    # Check available disk space (minimum 500GB recommended)
    available_space=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 500 ]; then
        print_warning "Available disk space: ${available_space}GB. Minimum 500GB recommended for Android builds."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_success "System requirements check completed"
}

# Function to setup build directory
setup_build_dir() {
    print_status "Setting up build directory..."
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    print_success "Build directory setup completed"
}

# Function to initialize and sync ROM sources
sync_sources() {
    print_status "Initializing and syncing ROM sources..."
    cd "$BUILD_DIR"
    
    # Initialize repo
    print_status "Initializing repository..."
    repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --git-lfs
    
    if [ $? -ne 0 ]; then
        print_error "Failed to initialize repository"
        exit 1
    fi
    
    # Sync sources
    print_status "Syncing sources (this may take a while)..."
    repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j"$SYNC_JOBS"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to sync sources"
        exit 1
    fi
    
    print_success "ROM sources synced successfully"
}

# Function to clean existing device repositories
clean_device_repos() {
    print_status "Cleaning existing device repositories..."
    cd "$BUILD_DIR"

    # Get repository paths from JSON
    local repos=$(get_repositories "$DEVICE_CONFIG_FILE")

    for repo in $repos; do
        local path=$(jq -r ".repositories.$repo.path" "$DEVICE_CONFIG_FILE")
        if [ -d "$path" ]; then
            print_status "Removing $path"
            rm -rf "$path"
        fi
    done

    print_success "Device repositories cleaned"
}

# Function to clone device-specific repositories
clone_device_repos() {
    print_status "Cloning device-specific repositories..."
    cd "$BUILD_DIR"

    # Get repository list from JSON
    local repos=$(get_repositories "$DEVICE_CONFIG_FILE")

    for repo in $repos; do
        # Check if repository is optional and skip if marked
        local optional=$(jq -r ".repositories.$repo.optional // false" "$DEVICE_CONFIG_FILE")
        local url=$(jq -r ".repositories.$repo.url" "$DEVICE_CONFIG_FILE")
        local branch=$(jq -r ".repositories.$repo.branch" "$DEVICE_CONFIG_FILE")
        local path=$(jq -r ".repositories.$repo.path" "$DEVICE_CONFIG_FILE")

        # Skip if URL is null or empty
        if [ "$url" = "null" ] || [ -z "$url" ]; then
            if [ "$optional" = "true" ]; then
                print_status "Skipping optional repository: $repo"
                continue
            else
                print_error "Required repository missing URL: $repo"
                exit 1
            fi
        fi

        print_status "Cloning $repo..."
        if ! git clone "$url" -b "$branch" "$path"; then
            if [ "$optional" = "true" ]; then
                print_warning "Failed to clone optional repository: $repo"
            else
                print_error "Failed to clone required repository: $repo"
                exit 1
            fi
        fi
    done

    print_success "All device repositories cloned successfully"
}

# Function to setup build environment and start compilation
build_rom() {
    print_status "Setting up build environment and starting compilation..."
    cd "$BUILD_DIR"
    
    # Source build environment
    print_status "Sourcing build environment..."
    source build/envsetup.sh
    
    # Setup device configuration
    print_status "Setting up device configuration..."
    lunch "lineage_${DEVICE}-${BUILD_VARIANT}"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to setup device configuration"
        exit 1
    fi
    
    # Run installclean if this is a clean build
    if [ "$CLEAN_FIRST" = true ]; then
        print_status "Running installclean for clean build..."
        make installclean
    fi
    
    # Get number of CPU cores for parallel compilation
    CORES=$(nproc)
    print_status "Starting build with $CORES parallel jobs..."

    # Start the build
    print_status "Building ROM (this will take several hours)..."
    mka bacon -j"$CORES"
    
    if [ $? -eq 0 ]; then
        print_success "ROM build completed successfully!"

        # Find the output file
        OUTPUT_FILE=$(find "$BUILD_DIR/out/target/product/$DEVICE" -maxdepth 1 -name "lineage-*.zip" | head -1)
        if [ -n "$OUTPUT_FILE" ]; then
            print_success "ROM file created: $OUTPUT_FILE"
            ls -lh "$OUTPUT_FILE"
        fi
    else
        print_error "ROM build failed!"
        exit 1
    fi
}

# Function to clean build (optional) - only for complete clean
clean_build() {
    print_status "Cleaning build directory..."
    cd "$BUILD_DIR"
    if [ -f "build/envsetup.sh" ]; then
        source build/envsetup.sh
        make installclean
    else
        print_warning "Build environment not found, skipping clean"
    fi
    print_success "Build directory cleaned"
}

# Main execution flow
main() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  $ROM_NAME Custom ROM Builder  ${NC}"
    if [ -n "$DEVICE" ]; then
        echo -e "${BLUE}  Device: $DEVICE_FULL_NAME     ${NC}"
    fi
    echo -e "${BLUE}================================${NC}"
    echo
    
    # Parse command line arguments
    SKIP_SYNC=false
    CLEAN_FIRST=false
    CLEAN_REPOS=false
    SKIP_CLONE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --device|-d)
                if [ -z "$2" ]; then
                    print_error "Device argument requires a value"
                    exit 1
                fi
                # Support both device name and full path
                if [ -f "$2" ]; then
                    DEVICE_CONFIG_FILE="$2"
                elif [ -f "$SCRIPT_DIR/devices/$2.json" ]; then
                    DEVICE_CONFIG_FILE="$SCRIPT_DIR/devices/$2.json"
                elif [ -f "$SCRIPT_DIR/devices/$2" ]; then
                    DEVICE_CONFIG_FILE="$SCRIPT_DIR/devices/$2"
                else
                    print_error "Device configuration not found: $2"
                    echo "Available devices:"
                    ls -1 "$SCRIPT_DIR/devices/"*.json 2>/dev/null | xargs -n1 basename | sed 's/.json$//' || echo "  No devices configured"
                    exit 1
                fi
                shift 2
                ;;
            --skip-sync)
                SKIP_SYNC=true
                shift
                ;;
            --clean)
                CLEAN_FIRST=true
                shift
                ;;
            --clean-repos)
                CLEAN_REPOS=true
                shift
                ;;
            --skip-clone)
                SKIP_CLONE=true
                shift
                ;;
            --variant)
                BUILD_VARIANT_OVERRIDE=true
                case $2 in
                    user|userdebug|eng)
                        BUILD_VARIANT="$2"
                        shift 2
                        ;;
                    *)
                        print_error "Invalid build variant: $2. Use user, userdebug, or eng"
                        exit 1
                        ;;
                esac
                ;;
            --help|-h)
                echo "Usage: $0 --device <device> [OPTIONS]"
                echo
                echo "Required:"
                echo "  --device, -d <name>   Device to build"
                echo "                        Use device name or path to JSON config file"
                echo
                echo "Options:"
                echo "  --skip-sync           Skip source sync (useful for rebuilds)"
                echo "  --clean               Clean build directory before building"
                echo "  --clean-repos         Clean and re-clone device repositories"
                echo "  --skip-clone          Skip cloning device repositories"
                echo "  --variant <variant>   Build variant: user, userdebug, eng (default: userdebug)"
                echo "  --help, -h            Show this help message"
                echo
                echo "Available devices:"
                ls -1 "$SCRIPT_DIR/devices/"*.json 2>/dev/null | xargs -n1 basename | sed 's/.json$//' | sed 's/^/  /' || echo "  No devices configured"
                echo
                echo "Examples:"
                echo "  $0 --device <device_name>              # Build for device"
                echo "  $0 -d <device_name> --variant user     # User variant build"
                echo "  $0 -d <device_name> --skip-sync        # Rebuild without syncing"
                echo "  $0 -d /path/to/custom.json             # Build with custom config"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Check if device is specified
    if [ -z "$DEVICE_CONFIG_FILE" ]; then
        print_error "No device specified. Use --device <name> to specify a device."
        echo
        echo "Available devices:"
        ls -1 "$SCRIPT_DIR/devices/"*.json 2>/dev/null | xargs -n1 basename | sed 's/.json$//' | sed 's/^/  /' || echo "  No devices configured"
        echo
        echo "Use --help for more information."
        exit 1
    fi

    # Load device configuration
    load_device_config "$DEVICE_CONFIG_FILE"

    # Show configuration
    echo -e "${YELLOW}Build Configuration:${NC}"
    echo "  ROM: $ROM_NAME"
    echo "  Device: $DEVICE ($DEVICE_FULL_NAME)"
    echo "  Config File: $DEVICE_CONFIG_FILE"
    echo "  Build Directory: $BUILD_DIR"
    echo "  Manifest Branch: $MANIFEST_BRANCH"
    echo "  Sync Jobs: $SYNC_JOBS"
    echo "  Build Variant: $BUILD_VARIANT"
    echo "  Skip Sync: $SKIP_SYNC"
    echo "  Clean First: $CLEAN_FIRST"
    echo "  Clean Repos: $CLEAN_REPOS"
    echo "  Skip Clone: $SKIP_CLONE"
    echo
    
    # Confirmation
    read -p "Continue with build? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Build cancelled by user"
        exit 0
    fi
    
    # Record start time
    START_TIME=$(date +%s)
    
    # Execute build steps
    check_requirements
    setup_build_dir
    
    # Note: Clean will be handled after build environment setup
    
    # Sync sources (unless skipped)
    if [ "$SKIP_SYNC" = false ]; then
        sync_sources
    else
        print_warning "Skipping source sync as requested"
        if [ ! -d "$BUILD_DIR/.repo" ]; then
            print_error "No existing repo found in $BUILD_DIR. Cannot skip sync."
            exit 1
        fi
    fi
    
    # Clean and re-clone device repos if requested
    if [ "$CLEAN_REPOS" = true ]; then
        clean_device_repos
    fi
    
    # Clone device repos unless skipped
    if [ "$SKIP_CLONE" = false ]; then
        clone_device_repos
    else
        print_warning "Skipping device repository cloning as requested"
        # Verify essential device tree exists
        local device_tree_path=$(jq -r '.repositories.device_tree.path' "$DEVICE_CONFIG_FILE")
        if [ ! -d "$BUILD_DIR/$device_tree_path" ]; then
            print_error "Device tree not found at $device_tree_path. Cannot skip cloning without existing device repos."
            exit 1
        fi
    fi
    
    build_rom
    
    # Calculate and display build time
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    HOURS=$((BUILD_TIME / 3600))
    MINUTES=$(((BUILD_TIME % 3600) / 60))
    SECONDS=$((BUILD_TIME % 60))
    
    echo
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}       BUILD COMPLETED!         ${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}Total build time: ${HOURS}h ${MINUTES}m ${SECONDS}s${NC}"
    echo
}

# Trap to handle script interruption
trap 'echo -e "\n${RED}Build interrupted by user${NC}"; exit 1' INT

# Run main function with all arguments
main "$@"
