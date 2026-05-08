#!/bin/bash
# publish-ep3-v2.sh
# ONE-COMMAND publish for Episode 3 v2 ("Salt").
#
# What this does, end-to-end:
#   1. Calls generate-audio-v3.py to produce the new ElevenLabs audio
#      (skips if a fresh audio file already exists from today)
#   2. Copies the new mp3 into audio/ with the -v2 suffix so Spotify
#      treats it as a new episode (new GUID, new filename, new pubDate)
#   3. Surgically removes the old ep003 entry from feed.xml
#   4. Inserts the new ep003-v2 entry at the top of the feed
#   5. Stages the script, prompts, outline, continuity, audio file, and feed
#   6. Commits and pushes to GitHub (so GitHub Pages serves the new audio
#      and Spotify pulls the new feed entry on its next refresh)
#
# Usage from Git Bash on Windows:
#   cd ~/CODE/ironline-podcast
#   bash engine/scripts/publish-ep3-v2.sh
#
# Total time: ~10 minutes (audio generation is the long part).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

EPISODE_DIR="$PROJECT_ROOT/series/the-future-economy/episodes/ep003"
AUDIO_META="$EPISODE_DIR/audio-metadata.json"
FEED_FILE="$PROJECT_ROOT/feed.xml"
TODAY=$(date +%Y-%m-%d)

# ── 1. Generate audio (skip if fresh) ─────────────────────────────────────────

NEED_AUDIO=true
if [ -f "$AUDIO_META" ]; then
    EXISTING_FILENAME=$(python3 -c "import json; print(json.load(open('$AUDIO_META'))['audio_filename'])" 2>/dev/null || echo "")
    if echo "$EXISTING_FILENAME" | grep -q "^${TODAY}_ep003"; then
        echo "Audio already generated today: $EXISTING_FILENAME — skipping generation."
        NEED_AUDIO=false
    fi
fi

if [ "$NEED_AUDIO" = true ]; then
    echo "=== STEP 1: Generating audio with ElevenLabs (v3, Jackson) ==="
    echo "    This will take 5-10 minutes."
    python3 "$SCRIPT_DIR/generate-audio-v3.py" the-future-economy 3
fi

# ── 2. Locate fresh audio ─────────────────────────────────────────────────────

AUDIO_SOURCE=$(python3 -c "import json; print(json.load(open('$AUDIO_META'))['audio_file'])")
if [ ! -f "$AUDIO_SOURCE" ]; then
    echo "ERROR: audio file referenced in metadata not found: $AUDIO_SOURCE"
    exit 1
fi

echo ""
echo "=== STEP 2: Copying audio into audio/ with -v2 suffix ==="
NEW_FILENAME="the-future-economy-ep003-v2.mp3"
NEW_DEST="$PROJECT_ROOT/audio/$NEW_FILENAME"
cp "$AUDIO_SOURCE" "$NEW_DEST"
FILE_SIZE=$(stat -f%z "$NEW_DEST" 2>/dev/null || stat --printf="%s" "$NEW_DEST" 2>/dev/null)
echo "    Copied: $NEW_DEST ($FILE_SIZE bytes)"

# ── 3. Build new RSS item ─────────────────────────────────────────────────────

NEW_GUID="the-future-economy-ep003-v2"
NEW_TITLE="The Future Economy — Salt"
NEW_AUDIO_URL="https://eggmcmark.github.io/ironline-podcast/audio/$NEW_FILENAME"
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
SUMMARY=$(python3 -c "import json; print(json.load(open('$EPISODE_DIR/metadata.json'))['summary'])")

NEW_ITEM=$(cat <<EOF
    <item>
      <title>$NEW_TITLE</title>
      <description><![CDATA[$SUMMARY]]></description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url="$NEW_AUDIO_URL" type="audio/mpeg" length="$FILE_SIZE" />
      <itunes:episode>3</itunes:episode>
      <itunes:season>1</itunes:season>
      <itunes:duration>40:00</itunes:duration>
      <itunes:explicit>no</itunes:explicit>
      <itunes:episodeType>full</itunes:episodeType>
      <guid isPermaLink="false">$NEW_GUID</guid>
    </item>
EOF
)

# ── 4. Surgical feed.xml swap ─────────────────────────────────────────────────

echo ""
echo "=== STEP 3: Updating feed.xml ==="
python3 << PYEOF
import re
from pathlib import Path

feed_path = Path("$FEED_FILE")
new_item = """$NEW_ITEM"""

text = feed_path.read_text(encoding="utf-8")

# Remove the old ep003 item by its exact GUID. The closing </guid> immediately
# after the GUID prevents matching a longer GUID like ep003-v2.
old_pattern = re.compile(
    r'    <item>\s*(?:(?!<item>).)*?<guid[^>]*>the-future-economy-ep003</guid>\s*</item>\s*',
    re.DOTALL
)
text, n = old_pattern.subn('', text)
print(f"    Removed {n} old ep003 item(s) from feed.xml")

# Also remove any prior ep003-v2 entries (idempotent re-run safety).
v2_pattern = re.compile(
    r'    <item>\s*(?:(?!<item>).)*?<guid[^>]*>the-future-economy-ep003-v2</guid>\s*</item>\s*',
    re.DOTALL
)
text, m = v2_pattern.subn('', text)
if m:
    print(f"    Removed {m} prior ep003-v2 item(s) (re-run cleanup)")

# Insert the new item at the top of the items list.
idx = text.find('    <item>')
if idx < 0:
    idx = text.find('  </channel>')
text = text[:idx] + new_item + '\n' + text[idx:]

# Validate XML before writing.
import xml.etree.ElementTree as ET
ET.fromstring(text)

feed_path.write_text(text, encoding="utf-8")
print("    Inserted new ep003-v2 item at top of feed.xml (XML validates)")
PYEOF

# ── 5. Stage and commit everything ────────────────────────────────────────────

echo ""
echo "=== STEP 4: Committing and pushing to GitHub ==="
cd "$PROJECT_ROOT"

# Stage the rewrite work, the new audio, the feed, the engine prompt updates,
# and the outline.
git add \
    feed.xml \
    "audio/$NEW_FILENAME" \
    series/the-future-economy/ \
    engine/prompts/write-episode.md \
    engine/scripts/publish-ep3-v2.sh \
    engine/scripts/republish-ep3-v2.sh \
    2>/dev/null || true

git commit -m "Republish: The Future Economy S1E03 — Salt (rewrite)

Replaces the original 'The Frontier' (ep003 v1, GUID the-future-economy-ep003)
with a new script and audio (GUID the-future-economy-ep003-v2). Old GUID
removed from feed.xml so Spotify and other clients pull the v2 as a fresh
episode rather than caching the v1.

Also updates:
- engine/prompts/write-episode.md — anti-slop discipline added
- series/the-future-economy/outline.md — pruned/rebuilt as v5; antagonist
  planted by Ep 3, every episode has a grounded engine
- continuity files updated for the rewrite
- v1 ep3 archived as script-v1.md, metadata-v1.json, writer-notes-v1.md"

git push origin main

echo ""
echo "=== DONE ==="
echo "  GUID:     $NEW_GUID"
echo "  Filename: $NEW_FILENAME"
echo "  URL:      $NEW_AUDIO_URL"
echo ""
echo "Spotify will pick up the new episode on its next feed refresh"
echo "(usually within an hour, sometimes same-day depending on their cache)."
