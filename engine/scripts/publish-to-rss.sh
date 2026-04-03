#!/bin/bash
# publish-to-rss.sh — Add episode to RSS feed and push to GitHub Pages
# Usage: ./publish-to-rss.sh <series-slug> <episode-number> <title> <description>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SERIES_SLUG="${1:?Usage: publish-to-rss.sh <series-slug> <episode-number> <title> <description>}"
EPISODE_NUM="${2:?Missing episode number}"
TITLE="${3:?Missing episode title}"
DESCRIPTION="${4:?Missing episode description}"

EPISODE_DIR="$PROJECT_ROOT/series/$SERIES_SLUG/episodes/ep$(printf '%03d' "$EPISODE_NUM")"
FEED_FILE="$PROJECT_ROOT/feed.xml"

# Find audio file
AUDIO_META="$EPISODE_DIR/audio-metadata.json"
if [ ! -f "$AUDIO_META" ]; then
    echo "ERROR: No audio metadata at $AUDIO_META — run generate-audio.sh first"
    exit 1
fi

AUDIO_SOURCE=$(python3 -c "import json; print(json.load(open('$AUDIO_META'))['audio_file'])")
FILE_SIZE=$(python3 -c "import json; print(json.load(open('$AUDIO_META'))['file_size_bytes'])")

# Copy audio to repo's audio directory for GitHub Pages serving
AUDIO_FILENAME="$(basename "$AUDIO_SOURCE")"
AUDIO_DEST="$PROJECT_ROOT/audio/$AUDIO_FILENAME"
cp "$AUDIO_SOURCE" "$AUDIO_DEST" 2>/dev/null || true

# Compute actual file size
if [ -f "$AUDIO_DEST" ]; then
    FILE_SIZE=$(stat -f%z "$AUDIO_DEST" 2>/dev/null || stat --printf="%s" "$AUDIO_DEST" 2>/dev/null || echo "$FILE_SIZE")
fi

# Build the RSS item
AUDIO_URL="https://eggmcmark.github.io/ironline-podcast/audio/$AUDIO_FILENAME"
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
GUID="$SERIES_SLUG-ep$(printf '%03d' "$EPISODE_NUM")"

# Determine season and episode numbers from series config
SEASON_NUM=1  # Default; could parse from series-config.yaml
EPISODE_PADDED=$(printf '%d' "$EPISODE_NUM")

# Escape XML special characters in title and description
TITLE_XML=$(echo "$TITLE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
DESC_XML=$(echo "$DESCRIPTION" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

NEW_ITEM="    <item>
      <title>$TITLE_XML</title>
      <description><![CDATA[$DESCRIPTION]]></description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url=\"$AUDIO_URL\" type=\"audio/mpeg\" length=\"$FILE_SIZE\" />
      <itunes:episode>$EPISODE_PADDED</itunes:episode>
      <itunes:season>$SEASON_NUM</itunes:season>
      <itunes:duration>40:00</itunes:duration>
      <itunes:explicit>no</itunes:explicit>
      <itunes:episodeType>full</itunes:episodeType>
      <guid isPermaLink=\"false\">$GUID</guid>
    </item>"

# Insert new item at the top of the item list (after the last channel metadata, before first existing item)
# Strategy: insert before the first <item> tag
if grep -q '<item>' "$FEED_FILE"; then
    # Insert before the first <item>
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
else
    echo "ERROR: Could not find insertion point in feed.xml"
    exit 1
fi

echo "RSS feed updated: $TITLE"
echo "  Audio URL: $AUDIO_URL"
echo "  GUID: $GUID"

# Git commit and push
cd "$PROJECT_ROOT"
if git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Committing and pushing to GitHub Pages..."
    git add feed.xml "audio/$AUDIO_FILENAME"
    git commit -m "Publish: $TITLE (S${SEASON_NUM}E${EPISODE_PADDED})"
    git push origin main
    echo "Pushed to GitHub Pages. Episode will be live shortly."
else
    echo "WARNING: Not a git repo. Feed updated locally but not pushed."
fi

# Update episode metadata
python3 -c "
import json, os
meta_path = '$EPISODE_DIR/audio-metadata.json'
with open(meta_path) as f:
    meta = json.load(f)
meta['published'] = {
    'rss_guid': '$GUID',
    'audio_url': '$AUDIO_URL',
    'pub_date': '$PUB_DATE',
    'feed_file': '$FEED_FILE'
}
with open(meta_path, 'w') as f:
    json.dump(meta, f, indent=2)
" 2>/dev/null || true

echo ""
echo "=== Publication Complete ==="
echo "  Title: $TITLE"
echo "  Feed: $FEED_FILE"
echo "  URL: $AUDIO_URL"
