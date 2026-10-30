# spz-chat

> Global, crew and DM chat with command autocomplete.

![version](https://img.shields.io/badge/version-1.9.0-ff6200) ![SPiceZ-Core](https://img.shields.io/badge/SPiceZ--Core-beta-18181b)

## Overview

Replaces the default chat. `T` opens it; messages go to global, crew or direct channels, and slash commands autocomplete. Closes itself whenever the player is teleported or a race / minigame takes over.

## Features

- Global, crew and DM channels
- Command autocomplete
- Hidden during the loading screen and spawn menu
- Auto-closes on teleports and mode changes

## Requirements

| Resource | Type |
|---|---|
| `ox_lib` | third-party |
| `spz-core` | SPiceZ module |
| `spz-identity` | SPiceZ module |

## Installation

Included in the [txAdmin recipe](https://github.com/SPiceZ21/spz-txrecipe). Manual install:

1. Download `spz-chat` from GitHub (latest release, or the repository) into your `resources` folder.
2. Add to `server.cfg`, after its requirements:

```cfg
ensure spz-chat
```

## Configuration

- `config.lua`

See the file for every option.

## Commands

| Command | Who | Description |
|---|---|---|
| `/help` | player | List every server feature and its key |

## Key binds

Rebindable in **Settings → Key Bindings → FiveM**.

| Action | Default |
|---|---|
| Open chat | `t` |

## Exports

| Export | Side |
|---|---|
| `Close` | client |
| `IsOpen` | client |

```lua
exports["spz-chat"]:Close(...)
```

---

Part of **SPiceZ-Core** — [documentation](https://github.com/SPiceZ21/Docs) · [all modules](https://github.com/SPiceZ21/Docs/blob/main/modules/README.md)
