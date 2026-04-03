#!/bin/bash
# publish-local.sh — Pull latest episode(s), generate audio, publish to RSS
# Run this locally after the remote agent has written new episodes.
#
# Usage: ./engine/publish-local.sh the-future-economy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SERIES_SLUG="${1:?Usage: publish-local.sh <series-slug>}"
SERIES_DIR="$PROJECT_ROOT/series/$SERIES_SLUG"

# Load env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Pull latest from remote
echo "Pulling latest from GitHub..."
cd "$PROJECT_ROOT"
git pull origin main

# Find episodes that have scripts but no audio
echo ""
echo "Scanning for unpublished episodes..."

PUBLISHED=0
for EP_DIR in "$SERIES_DIR"/episodes/ep*/; do
    [ -d "$EP_DIR" ] || continue
    SCRIPT_FILE="$EP_DIR/script.md"
    AUDIO_META="$EP_DIR/audio-metadata.json"

    if [ -f "$SCRIPT_FILE" ] && [ ! -f "$AUDIO_META" ]; then
        # Extract episode number from directory name
        EP_NUM=$(basename "$EP_DIR" | sed 's/ep0*//')
        EP_PADDED=$(basename "$EP_DIR")

        echo ""
        echo "=== Processing Episode $EP_NUM ==="

        # Check for metadata
        META_FILE="$EP_DIR/metadata.json"
        if [ -f "$META_FILE" ]; then
            TITLE=$(python3 -c "import json; print(json.load(open('$META_FILE'))['title'])")
        else
            TITLE="Episode $EP_NUM"
        fi
        echo "Title: $TITLE"

        # Generate audio
        echo "Generating audio (v3, Jackson)..."
        python3 "$SCRIPT_DIR/scripts/generate-audio-v3.py" "$SERIES_SLUG" "$EP_NUM"

        # Get audio info
        AUDIO_META="$EP_DIR/audio-metadata.json"
        AUDIO_SOURCE=$(python3 -c "import json; print(json.load(open('$AUDIO_META'))['audio_file'])")
        FILE_SIZE=$(python3 -c "import json; print(json.load(open('$AUDIO_META'))['file_size_bytes'])")

        # Copy to serve directory
        AUDIO_FILENAME="the-future-economy-${EP_PADDED}.mp3"
        cp "$AUDIO_SOURCE" "$PROJECT_ROOT/audio/$AUDIO_FILENAME"

        # Build RSS item
        AUDIO_URL="https://eggmcmark.github.io/ironline-podcast/audio/$AUDIO_FILENAME"
        PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
        GUID="the-future-economy-${EP_PADDED}"
        FULL_TITLE="The Future Economy — $TITLE"
        TITLE_XML=$(echo "$FULL_TITLE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

        if [ -f "$META_FILE" ]; then
            SUMMARY=$(python3 -c "import json; print(json.load(open('$META_FILE'))['summary'])")
        else
            SUMMARY="Episode $EP_NUM of The Future Economy"
        fi

        NEW_ITEM="    <item>
      <title>$TITLE_XML</title>
      <description><![CDATA[$SUMMARY]]></description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url=\"$AUDIO_URL\" type=\"audio/mpeg\" length=\"$FILE_SIZE\" />
      <itunes:episode>$EP_NUM</itunes:episode>
      <itunes:season>1</itunes:season>
      <itunes:duration>40:00</itunes:duration>
      <itunes:explicit>no</itunes:explicit>
      <itunes:episodeType>full</itunes:episodeType>
      <guid isPermaLink=\"false\">$GUID</guid>
    </item>"

        # Insert into feed.xml before first <item>
        FEED_FILE="$PROJECT_ROOT/feed.xml"
        TEMP_FILE=$(mktemp)
        INSERTED=false
        while IFS= read -r line; do
            if [[ "$line" == *"<item>"* ]] && [ "$INSERTED" = false ]; then
                echo "$NEW_ITEM" >> "$TEMP_FILE"
                INSERTED=true
            fi
            echo "$line" >> "$TEMP_FILE"
        done < "$FEED_FILE"
        mv "$TEMP_FILE" "$FEED_FILE"

        echo "RSS updated: $FULL_TITLE"
        PUBLISHED=$((PUBLISHED + 1))
    fi
done

if [ "$PUBLISHED" -eq 0 ]; then
    echo "No unpublished episodes found. Everything is up to date."
    exit 0
fi

# Commit and push
echo ""
echo "Committing and pushing $PUBLISHED episode(s)..."
cd "$PROJECT_ROOT"
git add -A
git commit -m "Publish: $PUBLISHED new episode(s) — audio generated and RSS updated

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
git push origin main

echo ""
echo "=== Done: $PUBLISHED episode(s) published ==="
