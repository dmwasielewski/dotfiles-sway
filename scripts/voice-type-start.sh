#!/bin/bash
# voice-type-start.sh — push-to-talk voice typing: start recording
# Called on Mod+T press from Sway. Stop recording by releasing Mod+T.

AUDIO_FILE="$HOME/.cache/voice-type/voice-input.wav"
PID_FILE="$HOME/.cache/voice-type/record.pid"
mkdir -p "$HOME/.cache/voice-type"

# Kill any leftover recording from a previous session
if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
fi
rm -f "$AUDIO_FILE"

# Record at 16kHz mono — optimal format for Whisper
arecord -f S16_LE -r 16000 -c 1 -t wav "$AUDIO_FILE" 2>/dev/null &
echo $! > "$PID_FILE"

notify-send "Voice Typing" "Recording — release Mod+T to transcribe" \
    -t 60000 -h string:x-canonical-private-synchronous:voice-typing 2>/dev/null || true
