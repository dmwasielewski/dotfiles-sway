#!/usr/bin/env python3
# voice-transcribe.py — transcribe audio with faster-whisper, then correct with LanguageTool

import sys
import os

audio_file = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.cache/voice-type/voice-input.wav"
)

from faster_whisper import WhisperModel
import language_tool_python

model = WhisperModel("small", device="cpu", compute_type="int8")
segments, info = model.transcribe(
    audio_file,
    language=None,
    beam_size=1,
    vad_filter=True,
)

# Polish and Russian share acoustic features — override false Russian detections
detected_lang = info.language if info.language in ("pl", "en") else "pl"

text = " ".join(s.text for s in segments).strip()

if not text:
    sys.exit(0)

tool = language_tool_python.LanguageTool(detected_lang)
text = language_tool_python.utils.correct(text, tool.check(text))
tool.close()

print(text)
