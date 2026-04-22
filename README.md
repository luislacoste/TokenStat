# TokenStat

A lightweight macOS menu bar app that shows your Claude API usage in real time.

Reads directly from the Anthropic OAuth API using the credentials stored by Claude Code — no API key required, no configuration beyond logging in.

## What it shows

- **Current Session** — utilization for the active 5-hour rolling window
- **7-Day Window** — utilization across the past 7 days
- **7-Day Sonnet** — Sonnet-specific utilization for the past 7 days

Each section shows a color-coded progress bar (green → red) and a countdown to the next reset.

## Requirements

- macOS 13 or later
- [Claude Code](https://claude.ai/code) installed and logged in (`claude login`)

## Build & run

```bash
bash build.sh
open TokenStat.app
```

## Versioning

TokenStat uses **Semantic Versioning**: `MAJOR.MINOR.PATCH`

| Number | When it changes | Example |
|--------|----------------|---------|
| **MAJOR** | A breaking change — the app works differently in a way that isn't backwards compatible, or a fundamental redesign | `1.x.x` → `2.0.0` |
| **MINOR** | A new feature added in a backwards-compatible way — something new you can use without changing how you already use the app | `1.0.x` → `1.1.0` |
| **PATCH** | A bug fix or small improvement — behavior is corrected but nothing new is added | `1.0.0` → `1.0.1` |

Current version: **1.0.0**

## Author

Made by Luis Lacoste

- Instagram: [@luislacoste_](https://www.instagram.com/luislacoste_)
- GitHub: [luislacoste](https://github.com/luislacoste)
