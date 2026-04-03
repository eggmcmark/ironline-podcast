#!/bin/bash
# orchestrate.sh — Weekly episode generation orchestrator
# Invoked by Windows Task Scheduler to produce one episode.
#
# Usage:
#   ./engine/orchestrate.sh the-future-economy
#   ./engine/orchestrate.sh the-future-economy --write-only
#   ./engine/orchestrate.sh the-future-economy --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/engine/logs"
mkdir -p "$LOG_DIR"

SERIES_SLUG="${1:?Usage: orchestrate.sh <series-slug> [--write-only|--dry-run]}"
MODE="${2:-full}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/${SERIES_SLUG}_${TIMESTAMP}.log"

echo "=== Ironline Podcast Engine ===" | tee "$LOG_FILE"
echo "Series: $SERIES_SLUG" | tee -a "$LOG_FILE"
echo "Mode: $MODE" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Validate series exists
SERIES_DIR="$PROJECT_ROOT/series/$SERIES_SLUG"
if [ ! -d "$SERIES_DIR" ]; then
    echo "ERROR: Series directory not found: $SERIES_DIR" | tee -a "$LOG_FILE"
    exit 1
fi

# Load environment
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Determine next episode number
EPISODE_LOG="$SERIES_DIR/continuity/episode-log.md"
LAST_EP=$(grep -oP '^\| \K\d+' "$EPISODE_LOG" 2>/dev/null | tail -1 || echo "0")
NEXT_EP=$((LAST_EP + 1))

# ─── SEASON BOUNDARY CHECK ────────────────────────────────────────────────────
# Season 1 has 14 episodes. Stop after that.
MAX_EPISODES=14
if [ "$NEXT_EP" -gt "$MAX_EPISODES" ]; then
    echo "Season 1 complete ($MAX_EPISODES episodes published). Stopping." | tee -a "$LOG_FILE"
    echo "To continue with Season 2, update MAX_EPISODES in orchestrate.sh" | tee -a "$LOG_FILE"
    exit 0
fi

echo "Next episode: $NEXT_EP of $MAX_EPISODES" | tee -a "$LOG_FILE"

# Create episode directory
EP_DIR="$SERIES_DIR/episodes/ep$(printf '%03d' "$NEXT_EP")"
mkdir -p "$EP_DIR"

# ─── PHASE 1: Write the episode ───────────────────────────────────────────────

echo "" | tee -a "$LOG_FILE"
echo "PHASE 1: Writing episode $NEXT_EP..." | tee -a "$LOG_FILE"

EP_PADDED=$(printf '%03d' "$NEXT_EP")

WRITER_PROMPT="You are the episode writer agent for the Ironline Podcast Engine.

Read and follow the instructions in: engine/prompts/write-episode.md

Your target series is: $SERIES_SLUG
Your target episode number is: $NEXT_EP

IMPORTANT: Before writing, read ALL of the following files:
- series/$SERIES_SLUG/story-bible.md (creative constitution)
- series/$SERIES_SLUG/outline.md (episode plan — find Episode $NEXT_EP)
- series/$SERIES_SLUG/series-config.yaml (parameters, mission)
- series/$SERIES_SLUG/world/*.md (all world docs)
- series/$SERIES_SLUG/characters/*.md (all character files)
- series/$SERIES_SLUG/continuity/arc-tracker.md (current state)
- series/$SERIES_SLUG/continuity/episode-log.md (what's published)
- ALL prior episode scripts in series/$SERIES_SLUG/episodes/*/script.md

Then:
1. Review the outline against the mission — update outline.md if needed
2. Write Episode $NEXT_EP following the writing standards (7000-8500 words)
3. Save script to series/$SERIES_SLUG/episodes/$EP_PADDED/script.md
4. Save metadata to series/$SERIES_SLUG/episodes/$EP_PADDED/metadata.json
5. Save writer notes to series/$SERIES_SLUG/episodes/$EP_PADDED/writer-notes.md
6. Update continuity/arc-tracker.md with new character states and threads
7. Update continuity/episode-log.md with the new entry
8. Create or update character files for any new characters introduced

Write the FULL episode. Do not truncate. Do not summarize. Do not ask for approval.
Write autonomously. The complete prose, start to finish."

if [ "$MODE" = "--dry-run" ]; then
    echo "DRY RUN: Would invoke Claude with writer prompt" | tee -a "$LOG_FILE"
    exit 0
fi

echo "Invoking Claude Code writer agent..." | tee -a "$LOG_FILE"
cd "$PROJECT_ROOT"
claude -p "$WRITER_PROMPT" --allowedTools "Read,Write,Edit,Glob,Grep,Bash" 2>&1 | tee -a "$LOG_FILE"

# Verify script was written
if [ ! -f "$EP_DIR/script.md" ]; then
    echo "ERROR: Episode script not created at $EP_DIR/script.md" | tee -a "$LOG_FILE"
    exit 1
fi

WORD_COUNT=$(wc -w < "$EP_DIR/script.md")
echo "Script written: $WORD_COUNT words" | tee -a "$LOG_FILE"

if [ "$MODE" = "--write-only" ]; then
    echo "=== Complete (write-only) ===" | tee -a "$LOG_FILE"
    exit 0
fi

# ─── PHASE 2: Generate audio ──────────────────────────────────────────────────

echo "" | tee -a "$LOG_FILE"
echo "PHASE 2: Generating audio (v3, Jackson)..." | tee -a "$LOG_FILE"

python3 "$SCRIPT_DIR/scripts/generate-audio-v3.py" "$SERIES_SLUG" "$NEXT_EP" 2>&1 | tee -a "$LOG_FILE"

# ─── PHASE 3: Publish to RSS ──────────────────────────────────────────────────

echo "" | tee -a "$LOG_FILE"
echo "PHASE 3: Publishing to RSS feed..." | tee -a "$LOG_FILE"

# Extract metadata
METADATA_FILE="$EP_DIR/metadata.json"
if [ -f "$METADATA_FILE" ]; then
    TITLE=$(python3 -c "import json; print(json.load(open('$METADATA_FILE'))['title'])")
    SUMMARY=$(python3 -c "import json; print(json.load(open('$METADATA_FILE'))['summary'])")
else
    TITLE="Episode $NEXT_EP"
    SUMMARY="Episode $NEXT_EP of The Future Economy"
fi

# Find the generated audio file
AUDIO_META="$EP_DIR/audio-metadata.json"
AUDIO_SOURCE=$(python3 -c "import json; print(json.load(open('$AUDIO_META'))['audio_file'])")
FILE_SIZE=$(python3 -c "import json; print(json.load(open('$AUDIO_META'))['file_size_bytes'])")

# Copy to serve directory with unique name
AUDIO_FILENAME="the-future-economy-ep${EP_PADDED}.mp3"
cp "$AUDIO_SOURCE" "$PROJECT_ROOT/audio/$AUDIO_FILENAME"

AUDIO_URL="https://eggmcmark.github.io/ironline-podcast/audio/$AUDIO_FILENAME"
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
GUID="the-future-economy-ep${EP_PADDED}"
FULL_TITLE="The Future Economy — $TITLE"

# Escape for XML
TITLE_XML=$(echo "$FULL_TITLE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

# Build new RSS item
NEW_ITEM="    <item>
      <title>$TITLE_XML</title>
      <description><![CDATA[$SUMMARY]]></description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url=\"$AUDIO_URL\" type=\"audio/mpeg\" length=\"$FILE_SIZE\" />
      <itunes:episode>$NEXT_EP</itunes:episode>
      <itunes:season>1</itunes:season>
      <itunes:duration>40:00</itunes:duration>
      <itunes:explicit>no</itunes:explicit>
      <itunes:episodeType>full</itunes:episodeType>
      <guid isPermaLink=\"false\">$GUID</guid>
    </item>"

# Insert before first existing <item>
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

echo "RSS updated: $FULL_TITLE" | tee -a "$LOG_FILE"

# ─── PHASE 4: Git commit and push ─────────────────────────────────────────────

echo "" | tee -a "$LOG_FILE"
echo "PHASE 4: Publishing to GitHub Pages..." | tee -a "$LOG_FILE"

cd "$PROJECT_ROOT"
git add -A
git commit -m "Publish: The Future Economy S1E$(printf '%02d' "$NEXT_EP") — $TITLE

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
git push origin main

echo "" | tee -a "$LOG_FILE"
echo "=== Episode $NEXT_EP of $MAX_EPISODES Complete ===" | tee -a "$LOG_FILE"
echo "Title: $FULL_TITLE" | tee -a "$LOG_FILE"
echo "Script: $EP_DIR/script.md ($WORD_COUNT words)" | tee -a "$LOG_FILE"
echo "Audio: audio/$AUDIO_FILENAME" | tee -a "$LOG_FILE"
echo "Feed: $FEED_FILE" | tee -a "$LOG_FILE"
echo "Finished: $(date)" | tee -a "$LOG_FILE"

if [ "$NEXT_EP" -eq "$MAX_EPISODES" ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "*** SEASON 1 COMPLETE ***" | tee -a "$LOG_FILE"
    echo "Next run will exit without generating." | tee -a "$LOG_FILE"
fi
