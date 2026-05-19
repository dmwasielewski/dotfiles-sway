#!/bin/bash
# voice-type-stop.sh — push-to-talk voice typing: stop recording, transcribe, inject text
# Called on Mod+T release from Sway.

PID_FILE="$HOME/.cache/voice-type/record.pid"
AUDIO_FILE="$HOME/.cache/voice-type/voice-input.wav"
TOOLBOX_CONTAINER="${TOOLBOX_CONTAINER:-damianf}"

# Stop recording
if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
fi

# Give arecord time to finalise the WAV header
sleep 0.3

if [ ! -f "$AUDIO_FILE" ]; then
    notify-send "Voice Typing" "No audio recorded" -t 3000 \
        -h string:x-canonical-private-synchronous:voice-typing 2>/dev/null || true
    exit 0
fi

notify-send "Voice Typing" "Transcribing..." -t 30000 \
    -h string:x-canonical-private-synchronous:voice-typing 2>/dev/null || true

# Run Whisper inside the selected toolbox (shared home dir makes the audio file accessible)
TEXT=$(toolbox run --container "$TOOLBOX_CONTAINER" python3 \
    ~/dotfiles-sway/scripts/voice-transcribe.py "$AUDIO_FILE" 2>/dev/null)

rm -f "$AUDIO_FILE"

if [ -n "$TEXT" ]; then
    wtype "$TEXT"
    notify-send "Voice Typing" "Done" -t 2000 \
        -h string:x-canonical-private-synchronous:voice-typing 2>/dev/null || true
else
    notify-send "Voice Typing" "No speech detected" -t 3000 \
        -h string:x-canonical-private-synchronous:voice-typing 2>/dev/null || true
fi
