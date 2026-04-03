#!/usr/bin/env python3
"""
generate-audio.py — Convert episode script to audio via ElevenLabs TTS
Usage: python generate-audio.py <series-slug> <episode-number>
"""

import json
import os
import re
import sys
import time
from pathlib import Path

# Config
CHUNK_SIZE = 4500  # chars per API request (ElevenLabs limit ~5000)
PAUSE_BETWEEN_CHUNKS = 1  # seconds, for rate limiting

def clean_text(raw: str) -> str:
    """Strip markdown formatting, keeping only prose."""
    # Remove YAML/markdown headers
    text = re.sub(r'^#.*$', '', raw, flags=re.MULTILINE)
    # Remove bold
    text = re.sub(r'\*\*', '', text)
    # Remove italics (but keep the text)
    text = re.sub(r'\*([^*]+)\*', r'\\1', text)
    # Remove horizontal rules
    text = re.sub(r'^---.*$', '', text, flags=re.MULTILINE)
    # Remove metadata line
    text = re.sub(r'^\*\[.*\]\*$', '', text, flags=re.MULTILINE)
    # Collapse multiple blank lines
    text = re.sub(r'\n{3,}', '\n\n', text)
    # Convert scene breaks to pauses
    text = text.replace('* * *', '\n\n')
    return text.strip()


def split_into_chunks(text: str, max_size: int) -> list:
    """Split text at paragraph boundaries."""
    paragraphs = text.split('\n\n')
    chunks = []
    current = ""

    for para in paragraphs:
        para = para.strip()
        if not para:
            continue
        if len(current) + len(para) + 2 > max_size and current:
            chunks.append(current.strip())
            current = para
        else:
            current = current + "\n\n" + para if current else para

    if current.strip():
        chunks.append(current.strip())

    return chunks


def generate_audio_chunk(text: str, voice_id: str, api_key: str, model_id: str, settings: dict) -> bytes:
    """Call ElevenLabs TTS API for a single chunk."""
    import urllib.request
    import urllib.error

    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
    payload = json.dumps({
        "text": text,
        "model_id": model_id,
        "voice_settings": settings
    }).encode('utf-8')

    req = urllib.request.Request(url, data=payload, headers={
        "xi-api-key": api_key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg"
    })

    try:
        with urllib.request.urlopen(req) as response:
            return response.read()
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8', errors='replace')
        print(f"  ERROR: HTTP {e.code}: {error_body}")
        sys.exit(1)


def main():
    if len(sys.argv) < 3:
        print("Usage: python generate-audio.py <series-slug> <episode-number>")
        sys.exit(1)

    series_slug = sys.argv[1]
    episode_num = int(sys.argv[2])
    episode_padded = f"ep{episode_num:03d}"

    # Paths
    project_root = Path(__file__).resolve().parent.parent.parent
    series_dir = project_root / "series" / series_slug
    episode_dir = series_dir / "episodes" / episode_padded
    audio_dir = project_root / "audio" / series_slug
    script_file = episode_dir / "script.md"

    audio_dir.mkdir(parents=True, exist_ok=True)

    if not script_file.exists():
        print(f"ERROR: Script not found: {script_file}")
        sys.exit(1)

    # Load env
    env_file = project_root / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, val = line.split('=', 1)
                os.environ.setdefault(key.strip(), val.strip())

    api_key = os.environ.get("ELEVENLABS_API_KEY", "")
    voice_id = os.environ.get("ELEVENLABS_VOICE_ID", "")

    if not api_key:
        print("ERROR: ELEVENLABS_API_KEY not set")
        sys.exit(1)
    if not voice_id:
        print("ERROR: ELEVENLABS_VOICE_ID not set")
        sys.exit(1)

    # Audio settings
    model_id = "eleven_multilingual_v2"
    voice_settings = {
        "stability": 0.50,
        "similarity_boost": 0.75,
        "style": 0.25,
        "use_speaker_boost": True
    }

    # Prepare text
    print(f"Reading script: {script_file}")
    raw_text = script_file.read_text(encoding='utf-8')
    clean = clean_text(raw_text)
    total_chars = len(clean)
    print(f"Clean text: {total_chars:,} characters")

    # Split into chunks
    chunks = split_into_chunks(clean, CHUNK_SIZE)
    print(f"Split into {len(chunks)} chunks")

    # Generate audio for each chunk
    audio_parts = []
    for i, chunk in enumerate(chunks):
        print(f"  Generating chunk {i+1}/{len(chunks)} ({len(chunk):,} chars)...", end=" ", flush=True)
        audio_data = generate_audio_chunk(chunk, voice_id, api_key, model_id, voice_settings)
        audio_parts.append(audio_data)
        print(f"OK ({len(audio_data):,} bytes)")
        if i < len(chunks) - 1:
            time.sleep(PAUSE_BETWEEN_CHUNKS)

    # Concatenate
    from datetime import date
    date_str = date.today().isoformat()
    output_file = audio_dir / f"{date_str}_{episode_padded}.mp3"

    print(f"\nConcatenating {len(audio_parts)} parts...")
    with open(output_file, 'wb') as f:
        for part in audio_parts:
            f.write(part)

    file_size = output_file.stat().st_size
    print(f"\n=== Audio Generation Complete ===")
    print(f"  File: {output_file}")
    print(f"  Size: {file_size:,} bytes ({file_size / 1024 / 1024:.1f} MB)")
    print(f"  Characters used: {total_chars:,}")
    print(f"  Voice: {voice_id}")
    print(f"  Model: {model_id}")

    # Write metadata
    meta = {
        "audio_file": str(output_file),
        "audio_filename": output_file.name,
        "generated_at": f"{date_str}T{time.strftime('%H:%M:%S')}Z",
        "voice_id": voice_id,
        "model_id": model_id,
        "characters_used": total_chars,
        "file_size_bytes": file_size,
        "series": series_slug,
        "episode": episode_num,
        "chunks": len(audio_parts)
    }
    meta_file = episode_dir / "audio-metadata.json"
    meta_file.write_text(json.dumps(meta, indent=2))
    print(f"  Metadata: {meta_file}")

    return str(output_file)


if __name__ == "__main__":
    main()
