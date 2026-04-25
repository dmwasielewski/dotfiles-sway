#!/usr/bin/env python3
# voice-transcribe.py — transcribe an audio file using faster-whisper (local AI)
# Usage: python3 voice-transcribe.py <audio_file>
# Language is auto-detected. Model: small (460 MB, good accuracy on CPU).
# First run loads the model from disk (~5-10s); download happens only once during setup.

import sys
import os

audio_file = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.cache/voice-type/voice-input.wav"
)

from faster_whisper import WhisperModel

model = WhisperModel("small", device="cpu", compute_type="int8")
segments, _ = model.transcribe(audio_file)
print(" ".join(s.text for s in segments).strip())
