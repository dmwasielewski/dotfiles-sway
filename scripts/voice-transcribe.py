#!/usr/bin/env python3
# voice-transcribe.py — transcribe audio with faster-whisper, correct English with Gemini

import sys
import os

audio_file = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.cache/voice-type/voice-input.wav"
)

from faster_whisper import WhisperModel

model = WhisperModel("small", device="cpu", compute_type="int8")
segments, info = model.transcribe(
    audio_file,
    language=None,
    beam_size=1,
    vad_filter=True,
    initial_prompt="The speaker uses either Polish or British English only. No other languages.",
)

is_polish = (info.language == "pl")

text = " ".join(s.text for s in segments).strip()

if not text:
    sys.exit(0)

if is_polish:
    print(text)
    sys.exit(0)

key_file = os.path.expanduser("~/.config/voice-type/gemini-api-key")
try:
    api_key = open(key_file).read().strip()
except FileNotFoundError:
    print(text)
    sys.exit(0)

from google import genai

client = genai.Client(api_key=api_key)
gemini_models = [
    model.strip()
    for model in os.getenv(
        "VOICE_TYPE_GEMINI_MODELS",
        "gemini-3.1-flash-lite,gemini-2.5-flash-lite",
    ).split(",")
    if model.strip()
]

prompt = f"""You are a UK English language tutor. The text below was spoken in English by a non-native speaker and transcribed from speech. Always treat it as spoken UK English regardless of how it looks.

Rewrite it as natural spoken UK English: fix grammar, verb tenses, word choice, prepositions, and sentence structure.
Keep the natural spoken flow — do NOT make it sound formal or written.
Return ONLY the corrected text, nothing else.

Text: {text}"""

corrected = text
for gemini_model in gemini_models:
    try:
        response = client.models.generate_content(
            model=gemini_model,
            contents=prompt,
        )
        candidate = response.text.strip()
        if candidate:
            corrected = candidate
            break
    except Exception:
        continue

print(corrected)
