#!/bin/bash
# generate-audio.sh — Convert episode script to audio via ElevenLabs TTS
# Usage: ./generate-audio.sh <series-slug> <episode-number>
# Example: ./generate-audio.sh the-future-economy 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

SERIES_SLUG="${1:?Usage: generate-audio.sh <series-slug> <episode-number>}"
EPISODE_NUM="${2:?Usage: generate-audio.sh <series-slug> <episode-number>}"
EPISODE_DIR="$PROJECT_ROOT/series/$SERIES_SLUG/episodes/ep$(printf '%03d' "$EPISODE_NUM")"
AUDIO_DIR="$PROJECT_ROOT/audio/$SERIES_SLUG"
SCRIPT_FILE="$EPISODE_DIR/script.md"

# Validate
if [ ! -f "$SCRIPT_FILE" ]; then
    echo "ERROR: Script not found at $SCRIPT_FILE"
    exit 1
fi

if [ -z "${ELEVENLABS_API_KEY:-}" ]; then
    echo "ERROR: ELEVENLABS_API_KEY not set in .env"
    exit 1
fi

# Read voice configuration from series config
SERIES_CONFIG="$PROJECT_ROOT/series/$SERIES_SLUG/series-config.yaml"
# Default voice settings (can be overridden by config)
VOICE_ID="${ELEVENLABS_VOICE_ID:-}"
MODEL_ID="eleven_multilingual_v2"
STABILITY="0.50"
SIMILARITY_BOOST="0.75"
STYLE="0.25"

if [ -z "$VOICE_ID" ]; then
    echo "ERROR: ELEVENLABS_VOICE_ID not set. Run voice audition first:"
    echo "  curl -s 'https://api.elevenlabs.io/v1/voices' -H 'xi-api-key: $ELEVENLABS_API_KEY' | python3 -c \"import json,sys; [print(f\\\"{v['voice_id']} | {v['name']}\\\") for v in json.load(sys.stdin)['voices']]\""
    exit 1
fi

# Strip markdown from script, prepare for TTS
echo "Preparing text from $SCRIPT_FILE..."
CLEAN_TEXT=$(cat "$SCRIPT_FILE" | \
    sed 's/^#.*//g' | \
    sed 's/\*\*//g' | \
    sed 's/\*//g' | \
    sed 's/^---.*//g' | \
    sed 's/^>.*//g' | \
    sed '/^$/N;/^\n$/d' | \
    sed 's/^[ \t]*//' | \
    tr '\r' ' ')

CHAR_COUNT=${#CLEAN_TEXT}
echo "Text prepared: $CHAR_COUNT characters"

# ElevenLabs limit is ~5000 chars per request. Split if needed.
CHUNK_SIZE=4500
CHUNK_DIR=$(mktemp -d)
CHUNK_NUM=0

mkdir -p "$AUDIO_DIR"

if [ "$CHAR_COUNT" -le "$CHUNK_SIZE" ]; then
    # Single request
    CHUNKS=("$CLEAN_TEXT")
else
    # Split at paragraph boundaries
    echo "Splitting into chunks (text is $CHAR_COUNT chars)..."
    CURRENT_CHUNK=""
    while IFS= read -r line; do
        if [ ${#CURRENT_CHUNK} -gt 0 ] && [ $((${#CURRENT_CHUNK} + ${#line})) -gt "$CHUNK_SIZE" ]; then
            CHUNK_NUM=$((CHUNK_NUM + 1))
            echo "$CURRENT_CHUNK" > "$CHUNK_DIR/chunk_$(printf '%03d' $CHUNK_NUM).txt"
            CURRENT_CHUNK=""
        fi
        if [ -n "$CURRENT_CHUNK" ]; then
            CURRENT_CHUNK="$CURRENT_CHUNK
$line"
        else
            CURRENT_CHUNK="$line"
        fi
    done <<< "$CLEAN_TEXT"
    # Write last chunk
    if [ -n "$CURRENT_CHUNK" ]; then
        CHUNK_NUM=$((CHUNK_NUM + 1))
        echo "$CURRENT_CHUNK" > "$CHUNK_DIR/chunk_$(printf '%03d' $CHUNK_NUM).txt"
    fi
    echo "Split into $CHUNK_NUM chunks"
fi

# Generate audio for each chunk
DATE_SLUG=$(date +%Y-%m-%d)
EPISODE_SLUG="ep$(printf '%03d' "$EPISODE_NUM")"
OUTPUT_FILE="$AUDIO_DIR/${DATE_SLUG}_${EPISODE_SLUG}.mp3"

if [ "$CHUNK_NUM" -eq 0 ]; then
    # Single chunk — direct output
    echo "Generating audio (single request)..."
    curl -s -X POST "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID" \
        -H "xi-api-key: $ELEVENLABS_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$(python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps({
    'text': text,
    'model_id': '$MODEL_ID',
    'voice_settings': {
        'stability': $STABILITY,
        'similarity_boost': $SIMILARITY_BOOST,
        'style': $STYLE,
        'use_speaker_boost': True
    }
}))
" <<< "$CLEAN_TEXT")" \
        --output "$OUTPUT_FILE"
    echo "Audio saved to $OUTPUT_FILE"
else
    # Multiple chunks — generate each, then concatenate
    PART_FILES=""
    for CHUNK_FILE in "$CHUNK_DIR"/chunk_*.txt; do
        CHUNK_NAME=$(basename "$CHUNK_FILE" .txt)
        PART_FILE="$CHUNK_DIR/${CHUNK_NAME}.mp3"
        echo "Generating audio for $CHUNK_NAME..."

        CHUNK_TEXT=$(cat "$CHUNK_FILE")
        curl -s -X POST "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID" \
            -H "xi-api-key: $ELEVENLABS_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$(python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps({
    'text': text,
    'model_id': '$MODEL_ID',
    'voice_settings': {
        'stability': $STABILITY,
        'similarity_boost': $SIMILARITY_BOOST,
        'style': $STYLE,
        'use_speaker_boost': True
    }
}))
" <<< "$CHUNK_TEXT")" \
            --output "$PART_FILE"

        PART_FILES="$PART_FILES $PART_FILE"
        # Rate limiting — ElevenLabs recommends spacing requests
        sleep 2
    done

    # Concatenate with ffmpeg if available, otherwise use Python
    if command -v ffmpeg &>/dev/null; then
        echo "Concatenating with ffmpeg..."
        # Create file list for ffmpeg
        FILELIST="$CHUNK_DIR/filelist.txt"
        for f in $PART_FILES; do
            echo "file '$f'" >> "$FILELIST"
        done
        ffmpeg -y -f concat -safe 0 -i "$FILELIST" -c copy "$OUTPUT_FILE" 2>/dev/null
    else
        echo "Concatenating with Python (ffmpeg not found)..."
        python3 -c "
import sys, glob, os
chunk_dir = '$CHUNK_DIR'
output = '$OUTPUT_FILE'
parts = sorted(glob.glob(os.path.join(chunk_dir, 'chunk_*.mp3')))
with open(output, 'wb') as out:
    for part in parts:
        with open(part, 'rb') as f:
            out.write(f.read())
print(f'Concatenated {len(parts)} parts')
"
    fi

    echo "Audio saved to $OUTPUT_FILE"
fi

# Cleanup
rm -rf "$CHUNK_DIR"

# Report
FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat --printf="%s" "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
echo ""
echo "=== Audio Generation Complete ==="
echo "  File: $OUTPUT_FILE"
echo "  Size: $FILE_SIZE bytes"
echo "  Characters: $CHAR_COUNT"
echo "  Voice ID: $VOICE_ID"
echo "  Model: $MODEL_ID"

# Write metadata
cat > "$EPISODE_DIR/audio-metadata.json" << EOF
{
    "audio_file": "$OUTPUT_FILE",
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "voice_id": "$VOICE_ID",
    "model_id": "$MODEL_ID",
    "characters_used": $CHAR_COUNT,
    "file_size_bytes": "$FILE_SIZE",
    "series": "$SERIES_SLUG",
    "episode": $EPISODE_NUM
}
EOF

echo "  Metadata: $EPISODE_DIR/audio-metadata.json"
