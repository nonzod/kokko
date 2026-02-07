#!/bin/bash
set -e

# Start PulseAudio daemon in system mode
pulseaudio --system --daemonize --no-cpu-limit --disable-shm=true 2>/dev/null || true
sleep 2

# Load ALSA card modules with retry for USB devices
echo "=== Loading ALSA sound cards ==="
for card in /proc/asound/card[0-9]*; do
    card_num=$(basename "$card" | sed 's/card//')
    for attempt in 1 2 3; do
        echo "Loading ALSA card $card_num (attempt $attempt)..."
        if pactl load-module module-alsa-card device_id="$card_num" 2>&1; then
            break
        fi
        sleep 2
    done
done
sleep 1

# Print available audio devices for debugging
echo "=== Available PulseAudio devices ==="
echo "--- Sinks (output) ---"
pactl list sinks short 2>&1 || true
echo "--- Sources (input) ---"
pactl list sources short 2>&1 || true
echo "==================================="

# Launch the application with all passed arguments
exec python3 -m linux_voice_assistant "$@"
