# claude_statusline

My Claude Code status line: [victor-statusline](https://github.com/victorrentea/victor-statusline)
(public domain / Unlicense) with a **Dracula colour theme** and **calendar days** instead of working
days. Everything needed is in this folder; nobody has to fetch the upstream repo.

```
Sonnet 5.5 200K/1M ↗91% / 3h53 ★★★★ ⊂ $3.4 demo@branch -9=76% / 5d22h
```

## Install (for a person or an agent)

```sh
./install.sh              # copies statusline-command.sh to ~/.claude/ and sets "statusLine" in settings.json
./install.sh --previous   # go back to the older token bar in previous/
```

`install.sh` backs up `settings.json` to `settings.json.bak-statusline` and changes only the
`statusLine` key (`{"type":"command","command":"~/.claude/statusline-command.sh","refreshInterval":1}`).
Needs `jq`, `awk`, `bc`, `python3`. Works on macOS and Linux. Windows: untested.

## What the bar shows

| Segment | Meaning |
|---|---|
| `Sonnet 5.5` | model |
| `200K/1M` (or `40K/200K • 20%`) | context used / window (% only shown for non-1M windows) |
| `↗91% / 3h53` | 5h quota left (arrow = on pace) and time until it resets; chip turns amber, then maroon, as it runs low |
| `★★★★` or `$0.3 -3m` | cost of the current/last turn, and `-3m` = minutes left on the prompt cache |
| `⊂ $3.4` | session total (the turn is a subset of it) |
| `demo@branch` | folder chip (colour per folder) and git branch (hidden on main/master) |
| `-9=76% / 5d22h` | weekly quota: pace vs. a straight line (`-` = ahead of budget), % left, time to reset |

## Changes from upstream (`upstream-victor-statusline-command.sh`, for `diff`)

1. **Dracula truecolor palette**, dark terminals only (a light theme keeps the original colours).
   Semantic colours kept: green ok, orange low, red alarm. Model name purple, context cyan/pink,
   turn cost pink, session total yellow, branch purple, weekly % cyan, cache clock purple,
   5h chip on Dracula selection background with a pink percentage, folder chip rotating through
   Dracula colours. The palette block is the `# --- Dracula` section near the top.
2. **Calendar days** for the weekly reset clock (`5d22h`, not `3wd22h`), and the weekly pace
   is measured on calendar time too: the `work()` function in the awk block counts every day
   (original: skipped Sat/Sun).

## Not installed on purpose

Upstream also ships optional quota hooks (`quota-state`, `quota-probe`, `quota-gate`). They are
**not** included: the probe calls Anthropic's OAuth usage endpoint, and the gate parks a terminal
when quota runs low. Without them the bar uses its own fallback heuristics. If wanted, take them
from the upstream repo and read them first.

`previous/` holds my earlier bar (`status_line_tokens.sh`, a token/context progress bar) and its
`statusLine` block, so it can be reinstalled with `./install.sh --previous`.
