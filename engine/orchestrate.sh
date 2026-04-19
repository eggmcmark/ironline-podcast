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

Target series: $SERIES_SLUG
Target episode: $NEXT_EP (padded: $EP_PADDED)

CRITICAL OUTPUT CONSTRAINTS — READ FIRST:

1. DO NOT compose the episode script as text in your chat responses. Prior runs
   timed out because the agent emitted 7500+ words as a single assistant message.
   Your chat output must be TERSE status updates only (one sentence per step).
   The script lives in files, not in your messages.

2. Write the script in CHUNKS to the file. No single tool call should contain
   more than ~2500 words of prose. A 7500-word episode must be built via at
   least 3 sequential file operations:
     - First: Write tool with section A (~2500 words). This creates the file.
     - Then: Bash 'cat >> ...path... <<'\"'\"'IRONLINE_EOF'\"'\"'' heredoc append
       with section B (~2500 words).
     - Then: Bash heredoc append again with section C (~2500 words).
     - Finally: Bash 'wc -w ...path...' to verify total length.

3. Before writing, read ALL context files:
   - engine/prompts/write-episode.md (writing standards — the constitution)
   - series/$SERIES_SLUG/story-bible.md
   - series/$SERIES_SLUG/outline.md (find Episode $NEXT_EP entry)
   - series/$SERIES_SLUG/series-config.yaml
   - series/$SERIES_SLUG/world/*.md
   - series/$SERIES_SLUG/characters/*.md (if any)
   - series/$SERIES_SLUG/continuity/arc-tracker.md
   - series/$SERIES_SLUG/continuity/episode-log.md
   - ALL prior episode scripts: series/$SERIES_SLUG/episodes/*/script.md

PROCESS:

Phase 1 — Read context (one terse status line).
Phase 2 — Plan internally: title, logline, ensemble POV structure, scene list,
          word target (7000-8500). Split the episode into 3 sections labeled
          A, B, C, each ~2500 words. Do not narrate this plan in chat.
Phase 3 — Write the script file in chunks as specified above. Output path:
          series/$SERIES_SLUG/episodes/$EP_PADDED/script.md
Phase 4 — Write metadata and notes:
          series/$SERIES_SLUG/episodes/$EP_PADDED/metadata.json
          series/$SERIES_SLUG/episodes/$EP_PADDED/writer-notes.md
Phase 5 — Update continuity files:
          series/$SERIES_SLUG/continuity/arc-tracker.md
          series/$SERIES_SLUG/continuity/episode-log.md
Phase 6 — If the outline has drifted from the mission, update outline.md.
          Otherwise leave it alone.

WRITING STANDARDS (apply in planning and drafting):
- 7000-8500 words total, no less, no more.
- Audio-first prose: written to be heard. Natural speech boundaries.
- Third person limited, past tense.
- Show, don't tell. No exposition dumps. No camp, no cheese.
- ENSEMBLE CAST: multiple POVs, different locations, different social strata.
- Each character speaks differently — check character descriptions in the
  arc-tracker and any character files before writing dialogue.
- The Compact equity economy is furniture in characters' lives, not the plot.
- Continue the arc from the prior episodes. Respect continuity strictly.
- Wry humor where it fits. End with resonance, not a cliffhanger.

Execute autonomously. Keep chat output terse — the script lives in files."

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
