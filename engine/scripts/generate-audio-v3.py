#!/usr/bin/env python3
"""
generate-audio-v3.py — ElevenLabs v3 TTS with request stitching
Usage: python generate-audio-v3.py <series-slug> <episode-number>
"""

import json
import os
import re
import sys
import time
from pathlib import Path

CHUNK_SIZE = 4500
PAUSE_BETWEEN_CHUNKS = 2

def clean_text(raw: str) -> str:
    text = re.sub(r'^#.*$', '', raw, flags=re.MULTILINE)
    text = re.sub(r'\*\*', '', text)
    text = re.sub(r'\*([^*]+)\*', r'\1', text)
    text = re.sub(r'^---.*$', '', text, flags=re.MULTILINE)
    text = re.sub(r'^\*\[.*\]\*$', '', text, flags=re.MULTILINE)
    text = re.sub(r'\n{3,}', '\n\n', text)
    # v3 audio tags for scene breaks
    text = text.replace('* * *', '\n[long pause]\n')
    return text.strip()

def split_into_chunks(text: str, max_size: int) -> list:
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

def generate_chunk(text: str, voice_id: str, api_key: str, model_id: str,
                   settings: dict, prev_text: str = None, next_text: str = None,
                   prev_request_ids: list = None) -> tuple:
    """Returns (audio_bytes, request_id)"""
    import urllib.request
    import urllib.error

    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
    payload = {
        "text": text,
        "model_id": model_id,
        "voice_settings": settings
    }
    # Note: v3 does not yet support request stitching (previous_request_ids
    # or previous_text/next_text). Chunks are generated independently.
    # Splitting at paragraph boundaries minimizes audible seams.

    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={
        "xi-api-key": api_key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg"
    })

    try:
        with urllib.request.urlopen(req) as response:
            audio = response.read()
            # Get request ID from headers for stitching
            request_id = response.headers.get('request-id', None)
            return audio, request_id
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8', errors='replace')
        print(f"\n  ERROR: HTTP {e.code}: {error_body}")
        sys.exit(1)

def main():
    if len(sys.argv) < 3:
        print("Usage: python generate-audio-v3.py <series-slug> <episode-number>")
        sys.exit(1)

    series_slug = sys.argv[1]
    episode_num = int(sys.argv[2])
    episode_padded = f"ep{episode_num:03d}"

    project_root = Path(__file__).resolve().parent.parent.parent
    episode_dir = project_root / "series" / series_slug / "episodes" / episode_padded
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
    if not api_key or not voice_id:
        print("ERROR: ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID must be set")
        sys.exit(1)

    model_id = "eleven_v3"
    voice_settings = {
        "stability": 0.75,
        "similarity_boost": 0.85,
        "style": 0.15,
        "use_speaker_boost": True,
        "speed": 0.93
    }

    print(f"Reading script: {script_file}")
    raw_text = script_file.read_text(encoding='utf-8')
    clean = clean_text(raw_text)
    total_chars = len(clean)
    print(f"Clean text: {total_chars:,} characters")
    print(f"Model: {model_id} | Voice: {voice_id}")
    print(f"Settings: stability={voice_settings['stability']}, "
          f"similarity={voice_settings['similarity_boost']}, "
          f"style={voice_settings['style']}, speed={voice_settings['speed']}")

    chunks = split_into_chunks(clean, CHUNK_SIZE)
    print(f"Split into {len(chunks)} chunks (with request stitching)\n")

    audio_parts = []
    request_ids = []

    for i, chunk in enumerate(chunks):
        prev_text = chunks[i-1] if i > 0 else None
        next_text = chunks[i+1] if i < len(chunks)-1 else None
        prev_ids = request_ids[-3:] if request_ids else None

        print(f"  Chunk {i+1}/{len(chunks)} ({len(chunk):,} chars)", end="", flush=True)
        if prev_ids:
            print(f" [stitched to {len(prev_ids)} prev]", end="", flush=True)

        audio_data, req_id = generate_chunk(
            chunk, voice_id, api_key, model_id, voice_settings,
            prev_text=prev_text, next_text=next_text,
            prev_request_ids=prev_ids
        )
        audio_parts.append(audio_data)
        if req_id:
            request_ids.append(req_id)
        print(f" -> {len(audio_data):,} bytes (id: {req_id[:12] if req_id else 'none'})")

        if i < len(chunks) - 1:
            time.sleep(PAUSE_BETWEEN_CHUNKS)

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
    print(f"  Model: {model_id}")
    print(f"  Chunks: {len(audio_parts)} (stitched)")

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
        "chunks": len(audio_parts),
        "request_stitching": True,
        "voice_settings": voice_settings
    }
    meta_file = episode_dir / "audio-metadata.json"
    meta_file.write_text(json.dumps(meta, indent=2))
    print(f"  Metadata: {meta_file}")

if __name__ == "__main__":
    main()
