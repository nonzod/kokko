#!/bin/bash
set -e

# Debug: show ALSA devices on this node
echo "=== ALSA devices on node ==="
cat /proc/asound/cards 2>&1 || true
echo "--- ALSA capture devices ---"
arecord -l 2>&1 || true
echo "--- ALSA playback devices ---"
aplay -l 2>&1 || true

# Start PulseAudio daemon in system mode
pulseaudio --system --daemonize --no-cpu-limit --disable-shm=true 2>/dev/null || true
sleep 2

# Load ALSA card modules
echo "=== Loading ALSA sound cards ==="
for card in /proc/asound/card[0-9]*; do
    card_num=$(basename "$card" | sed 's/card//')
    echo "Loading ALSA card $card_num..."

    # Try module-alsa-card first (full card with sink+source)
    if pactl load-module module-alsa-card device_id="$card_num" 2>/dev/null; then
        echo "  -> loaded as alsa-card"
        continue
    fi

    # Fallback: load as source-only (capture-only devices like USB mics)
    if [ -e "/dev/snd/pcmC${card_num}D0c" ]; then
        if pactl load-module module-alsa-source device="hw:${card_num},0" source_name="alsa_input.${card_num}.usb" 2>/dev/null; then
            echo "  -> loaded as alsa-source (capture only)"
            continue
        fi
    fi

    # Fallback: load as sink-only (playback-only devices)
    if [ -e "/dev/snd/pcmC${card_num}D0p" ]; then
        if pactl load-module module-alsa-sink device="hw:${card_num},0" sink_name="alsa_output.${card_num}.usb" 2>/dev/null; then
            echo "  -> loaded as alsa-sink (playback only)"
            continue
        fi
    fi

    echo "  -> FAILED to load card $card_num"
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
