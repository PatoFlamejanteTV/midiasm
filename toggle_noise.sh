#!/bin/bash

# Noise Build Toggle Script
# Toggles the NOISE_BUILD flag on/off and verifies the build works

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Config file to persist the setting
CONFIG_FILE="$PROJECT_DIR/.noise_build_config"

# Function to display usage
usage() {
    echo "Usage: $0 [on|off|toggle|status]"
    echo ""
    echo "Commands:"
    echo "  on       - Enable NOISE_BUILD and compile"
    echo "  off      - Disable NOISE_BUILD and compile"
    echo "  toggle   - Toggle NOISE_BUILD and compile"
    echo "  status   - Show current NOISE_BUILD status"
    exit 1
}

# Function to check if noise is enabled
is_noise_enabled() {
    if [ -f "$CONFIG_FILE" ] && grep -q "NOISE_BUILD=1" "$CONFIG_FILE"; then
        return 0
    else
        return 1
    fi
}

# Function to show status
show_status() {
    if is_noise_enabled; then
        echo "NOISE_BUILD is currently: ON"
    else
        echo "NOISE_BUILD is currently: OFF"
    fi
}

# Function to enable noise build
enable_noise() {
    echo "Enabling NOISE_BUILD..."
    mkdir -p "$PROJECT_DIR"
    echo "NOISE_BUILD=1" > "$CONFIG_FILE"
    echo "Building with NOISE_BUILD enabled..."
    if NOISE=1 make clean && NOISE=1 make all; then
        echo "✓ NOISE_BUILD enabled successfully"
        show_status
        return 0
    else
        echo "✗ Build failed with NOISE_BUILD enabled"
        rm -f "$CONFIG_FILE"
        return 1
    fi
}

# Function to disable noise build
disable_noise() {
    echo "Disabling NOISE_BUILD..."
    rm -f "$CONFIG_FILE"
    echo "Building with NOISE_BUILD disabled..."
    if make clean && make all; then
        echo "✓ NOISE_BUILD disabled successfully"
        show_status
        return 0
    else
        echo "✗ Build failed with NOISE_BUILD disabled"
        return 1
    fi
}

# Parse command
COMMAND="${1:-toggle}"

case "$COMMAND" in
    on)
        enable_noise
        ;;
    off)
        disable_noise
        ;;
    toggle)
        if is_noise_enabled; then
            disable_noise
        else
            enable_noise
        fi
        ;;
    status)
        show_status
        ;;
    *)
        usage
        ;;
esac
