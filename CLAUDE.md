# Ironline Podcast Engine

Autonomous podcast generation system. Each series lives in `series/<series-name>/` with its own story bible, outline, characters, and episodes. The engine orchestrates weekly episode generation, audio conversion, and RSS publishing.

## How It Works

When invoked by the weekly cron (via `engine/orchestrate.sh`), the agent:

1. **Reads** the target series config (`series/<name>/series-config.yaml`)
2. **Reviews** the full story arc (`series/<name>/outline.md`) and all prior episodes
3. **Evaluates** continuity (`series/<name>/continuity/`) for consistency and mission alignment
4. **Improves** the outline if the arc has drifted from the series mission
5. **Writes** the next episode script to `series/<name>/episodes/epNNN/script.md`
6. **Generates** audio via ElevenLabs (`engine/scripts/generate-audio.sh`)
7. **Publishes** to RSS feed (`engine/scripts/publish-to-rss.sh`)
8. **Commits and pushes** to GitHub Pages for podcast distribution

## Project Structure

```
ironline-podcast/
├── CLAUDE.md                  ← You are here
├── engine/                    ← Reusable podcast engine
│   ├── orchestrate.sh         ← Cron entry point
│   ├── scripts/
│   │   ├── generate-audio.sh  ← ElevenLabs TTS pipeline
│   │   ├── publish-to-rss.sh  ← RSS feed updater + git push
│   │   └── concat-audio.ps1   ← PowerShell audio concatenation
│   ├── prompts/
│   │   └── write-episode.md   ← Episode writer agent prompt
│   └── templates/
│       └── series-config.template.yaml
│
├── series/                    ← One directory per series
│   └── the-future-economy/
│       ├── series-config.yaml
│       ├── story-bible.md
│       ├── outline.md
│       ├── characters/
│       ├── world/
│       ├── episodes/
│       │   └── ep001/
│       │       ├── script.md
│       │       ├── metadata.json
│       │       └── writer-notes.md
│       └── continuity/
│           ├── arc-tracker.md
│           └── episode-log.md
│
├── audio/                     ← Generated audio by series
│   └── the-future-economy/
├── feed.xml                   ← RSS feed (GitHub Pages serves this)
├── cover.jpg                  ← Podcast artwork
└── .env                       ← API keys (never commit)
```

## Adding a New Series

1. Copy `engine/templates/series-config.template.yaml` to `series/<new-name>/series-config.yaml`
2. Create `story-bible.md` with world, tone, and rules
3. Create `outline.md` with the full series arc
4. Add character files to `characters/`
5. Add world-building docs to `world/`
6. Update `engine/orchestrate.sh` to include the new series
7. The engine handles the rest

## Writing Standards

- **Audio-first**: Every sentence is written to be heard, not read
- **40-minute episodes**: ~7,000-8,500 words at narration pace (~180 wpm)
- **Show, don't tell**: No exposition dumps. Reveal through scene, dialogue, detail
- **Fractal structure**: Each episode is a complete story that mirrors the whole
- **Character consistency**: Voices, speech patterns, and behaviors must be tracked across episodes
- **No camp, no cheese**: Treat the audience as intelligent adults
- **Earned complexity**: Go deep on details only when it moves the story forward
- **Realistic humans**: People are contradictory, surprising, and recognizable across any era

## Environment

- API keys in `.env` (ELEVENLABS_API_KEY required)
- Audio served via GitHub Pages at https://eggmcmark.github.io/ironline-podcast/
- RSS feed at feed.xml in repo root
- Claude Code CLI used as the autonomous agent runtime
