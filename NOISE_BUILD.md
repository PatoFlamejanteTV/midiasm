# NOISE_BUILD Toggle Script

This script provides a convenient way to toggle the `NOISE_BUILD` flag on and off for the midiasm project.

## Usage

```bash
./toggle_noise.sh [command]
```

## Commands

- `on` - Enable NOISE_BUILD and compile
- `off` - Disable NOISE_BUILD and compile  
- `toggle` - Toggle NOISE_BUILD state and compile (default if no command given)
- `status` - Show current NOISE_BUILD status without compiling

## Examples

```bash
# Check current status
bash toggle_noise.sh status

# Enable noise build mode
bash toggle_noise.sh on

# Disable noise build mode
bash toggle_noise.sh off

# Toggle between modes
bash toggle_noise.sh toggle
```

## How It Works

- The script maintains a configuration file (`.noise_build_config`) in the project root
- Each build automatically cleans and rebuilds the project with the appropriate flag
- The `NOISE` environment variable is set when building with noise mode enabled
- The kernel assembly has been fixed to support proper label scoping with the NOISE_BUILD flag

## Configuration

The configuration state is stored in `.noise_build_config` in the project root.
