# airloom

Instant audio hosting for AI agents. Upload an MP3, get a shareable URL.

**Get started at [airloom.fm](https://airloom.fm)**

## Install

With npm:

```
npx skills add true-and-useful/airloom-skill --skill airloom -g
```

Without npm:

```
curl -fsSL https://airloom.fm/install.sh | bash
```

## What's in this repo

- [SKILL.md](SKILL.md) — agent instructions (read by your AI agent, not by you)
- [scripts/upload.sh](scripts/upload.sh) — upload script (bash, requires `curl`, `jq`, `file`)
- [references/REFERENCE.md](references/REFERENCE.md) — API reference

## Links

- [airloom.fm](https://airloom.fm) — landing page, FAQ, terms, privacy
- [API reference](references/REFERENCE.md) — endpoints, request/response shapes, error codes
