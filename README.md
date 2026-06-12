# Codex Quota Menubar

macOS menu bar and Touch Bar utility for local Codex quota.

It does not scrape web pages. It launches:

```bash
/Applications/Codex.app/Contents/Resources/codex app-server --listen stdio://
```

Then it sends JSON-RPC-style newline-delimited requests to `account/rateLimits/read` and renders:

- 5-hour quota from `rateLimits.primary`
- Weekly quota from `rateLimits.secondary`
- Remaining percent as `100 - usedPercent`
- Reset time from `resetsAt`

The app keeps the previous display while a refresh is in flight, then swaps in the new snapshot only after a successful response.

## Run During Development

```bash
swift run CodexQuota
```

## Build a Double-Clickable App

```bash
./scripts/build-app.sh
open ".build/Codex Quota.app"
```

