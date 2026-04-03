#!/bin/bash
# orchestrate.sh — Weekly episode generation orchestrator
# Invoked by Windows Task Scheduler (or manually) to produce one episode.
#
# Usage:
#   ./engine/orchestrate.sh the-future-economy
#   ./engine/orchestrate.sh the-future-economy --write-only   (skip audio+publish)
#   ./engine/orchestrate.sh the-future-economy --dry-run      (plan but don't execute)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/engine/logs"
mkdir -p "$LOG_DIR"

SERIES_SLUG="${1:?Usage: orchestrate.sh <series-slug> [--write-only|--dry-run]}"
MODE="${2:-full}"  # full, --write-only, --dry-run

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

# Determine next episode number from episode log
EPISODE_LOG="$SERIES_DIR/continuity/episode-log.md"
LAST_EP=$(grep -oP '^\| \K\d+' "$EPISODE_LOG" 2>/dev/null | tail -1 || echo "0")
NEXT_EP=$((LAST_EP + 1))
echo "Next episode: $NEXT_EP" | tee -a "$LOG_FILE"

# Create episode directory
EP_DIR="$SERIES_DIR/episodes/ep$(printf '%03d' "$NEXT_EP")"
mkdir -p "$EP_DIR"

# ─── PHASE 1: Write the episode ───────────────────────────────────────────────

echo "" | tee -a "$LOG_FILE"
echo "PHASE 1: Writing episode $NEXT_EP..." | tee -a "$LOG_FILE"

WRITER_PROMPT="You are the episode writer agent for the Ironline Podcast Engine.

Read and follow the instructions in: engine/prompts/write-episode.md

Your target series is: $SERIES_SLUG
Your target episode number is: $NEXT_EP

Execute the full writing process:
1. Read ALL series files (story bible, outline, characters, world, continuity, prior episodes)
2. Review the outline against the mission — update if needed
3. Write Episode $NEXT_EP following the writing standards
4. Save the script to series/$SERIES_SLUG/episodes/ep$(printf '%03d' "$NEXT_EP")/script.md
5. Save metadata to series/$SERIES_SLUG/episodes/ep$(printf '%03d' "$NEXT_EP")/metadata.json
6. Save writer notes to series/$SERIES_SLUG/episodes/ep$(printf '%03d' "$NEXT_EP")/writer-notes.md
7. Update continuity/arc-tracker.md and continuity/episode-log.md

Write the FULL episode. Target 7000-8500 words. Do not ask for approval — write autonomously.
Do not truncate. Do not summarize. Write the complete prose."

if [ "$MODE" = "--dry-run" ]; then
    echo "DRY RUN: Would invoke Claude with writer prompt" | tee -a "$LOG_FILE"
    echo "$WRITER_PROMPT" >> "$LOG_FILE"
else
    echo "Invoking Claude Code writer agent..." | tee -a "$LOG_FILE"
    cd "$PROJECT_ROOT"
    claude -p "$WRITER_PROMPT" --allowedTools "Read,Write,Edit,Glob,Grep,Bash" 2>&1 | tee -a "$LOG_FILE"
fi

# Verify script was written
if [ ! -f "$EP_DIR/script.md" ] && [ "$MODE" != "--dry-run" ]; then
    echo "ERROR: Episode script not created at $EP_DIR/script.md" | tee -a "$LOG_FILE"
    exit 1
fi

if [ "$MODE" = "--write-only" ] || [ "$MODE" = "--dry-run" ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "=== Complete (write-only mode) ===" | tee -a "$LOG_FILE"
    echo "Script: $EP_DIR/script.md" | tee -a "$LOG_FILE"
    exit 0
fi

# ─── PHASE 2: Generate audio ──────────────────────────────────────────────────

echo "" | tee -a "$LOG_FILE"
echo "PHASE 2: Generating audio..." | tee -a "$LOG_FILE"

bash "$SCRIPT_DIR/scripts/generate-audio.sh" "$SERIES_SLUG" "$NEXT_EP" 2>&1 | tee -a "$LOG_FILE"

# ─── PHASE 3: Publish to RSS ──────────────────────────────────────────────────

echo "" | tee -a "$LOG_FILE"
echo "PHASE 3: Publishing to RSS feed..." | tee -a "$LOG_FILE"

# Extract title and summary from metadata
METADATA_FILE="$EP_DIR/metadata.json"
if [ -f "$METADATA_FILE" ]; then
    TITLE=$(python3 -c "import json; print(json.load(open('$METADATA_FILE'))['title'])")
    SUMMARY=$(python3 -c "import json; print(json.load(open('$METADATA_FILE'))['summary'])")
else
    TITLE="Episode $NEXT_EP"
    SUMMARY="Episode $NEXT_EP of The Future Economy"
fi

FULL_TITLE="The Future Economy — $TITLE"

bash "$SCRIPT_DIR/scripts/publish-to-rss.sh" "$SERIES_SLUG" "$NEXT_EP" "$FULL_TITLE" "$SUMMARY" 2>&1 | tee -a "$LOG_FILE"

# ─── Done ──────────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOG_FILE"
echo "=== Episode $NEXT_EP Complete ===" | tee -a "$LOG_FILE"
echo "Script: $EP_DIR/script.md" | tee -a "$LOG_FILE"
echo "Audio: audio/$SERIES_SLUG/" | tee -a "$LOG_FILE"
echo "Feed: feed.xml" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "Finished: $(date)" | tee -a "$LOG_FILE"
