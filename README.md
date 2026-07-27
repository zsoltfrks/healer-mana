<div align="center">

<img src="assets/logo.png" alt="HealerMana logo" width="72" height="72" />

# HealerMana

**Keep an eye on your healer's mana. Nothing else.**

A lightweight World of Warcraft addon that shows every healer in your dungeon group
with their spec icon, name, and mana percentage. The way the old healer mana
WeakAura did before the addon sweep took it away.

![WoW](<https://img.shields.io/badge/WoW-Midnight%20(12.0.1)-1a1a1a>)
![Version](https://img.shields.io/badge/version-1.0-4a90d9)
![Masque](https://img.shields.io/badge/Masque-supported-c8873c)
![Dependencies](https://img.shields.io/badge/dependencies-none-4caf50)

<img width="749" alt="HealerMana in game" src="https://github.com/user-attachments/assets/8fcd999d-b6c1-4510-89ac-3c4d015843e8" />

</div>

## Features

- **Automatic healer detection** — reads assigned group roles, so off-spec players never show up by mistake.
- **Spec icon + name + mana %** — one clean row per healer, no bars, no clutter.
- **Drink awareness** — the icon swaps to a food icon while a healer is drinking.
- **Range fade** — out-of-range healers dim to 60% alpha.
- **Dungeon only** — the display stays hidden everywhere except 5-player instances.
- **Fully movable** — drag it anywhere, position is saved per account.
- **In-game settings panel** — font, outline, scale, text sizes and offsets, all applied live.
- **Masque support** — icons are skinned automatically if Masque is installed.
- **Taint-resistant mana reads** — keeps working when Blizzard hides power values behind secret returns.

## Installation

1. Download the repository (**Code → Download ZIP**) or clone it.
2. Extract it into your addons folder:
   ```text
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Rename the folder to `HealerMana`.
4. Restart the game, or run `/reload` if WoW is already open.

> [!IMPORTANT]
> The folder name **must** match the `.toc` file name. A GitHub download extracts as
> `healer-mana` or `healer-mana-main`, which WoW will not load — rename it to `HealerMana`.

Verify it loaded with `/hmtest`; a preview row using your own character should appear.

## Commands

| Command   | Description                                                                                                                                                                               |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/hm`     | Toggles **edit mode** and prints a role summary of your group to chat. A drag handle appears above the healer rows — move them where you want, then click the lock icon to save and exit. |
| `/hms`    | Opens the **settings panel**.                                                                                                                                                             |
| `/hmtest` | Toggles a **preview row** built from your own character, so you can tune the layout without being in a dungeon.                                                                           |

## Settings

Open the panel with `/hms`. Everything applies instantly and persists across sessions.

| Section           | What it does                                                                   |
| ----------------- | ------------------------------------------------------------------------------ |
| **Font**          | Friz Quadrata, Morpheus, Arial Narrow, or Skurri.                              |
| **Outline**       | None, Outline, or Thick.                                                       |
| **Scale**         | 0.5×–2.0× overall size of the display.                                         |
| **Name**          | Font size and X/Y offset of the healer name.                                   |
| **Mana%**         | Font size and X/Y offset of the percentage text.                               |
| **Quick actions** | Reload the UI, or reset every setting and the saved position back to defaults. |
| **Footer**        | Toggle the preview row, and unlock/lock the anchor without leaving the panel.  |

## How it works

Healers are detected purely from `UnitGroupRolesAssigned`, and the list is rebuilt whenever
the roster or role assignments change. Frames only exist while you are inside a 5-player
instance — outside of one, the addon hides everything and skips all processing.

> Since patch 12.0, `UnitPower` can return _secret_ values on tainted execution paths, which
> breaks any addon that does arithmetic on the result. HealerMana walks a fallback chain until
> it gets a usable number:
>
> 1. `UnitPower` inside a `securecallfunction` — fastest, works outside restrictions.
> 2. The power bar widget of an existing party frame (Blizzard default, compact, raid-style, or ElvUI) — widget values stay readable when the API values do not.
> 3. The last known cached percentage, refreshed on every clean `UNIT_POWER_UPDATE` event.
>
> The result is a percentage that keeps updating through combat instead of dropping to zero.

## Compatibility

|                          |                                                                          |
| ------------------------ | ------------------------------------------------------------------------ |
| **Game version**         | Retail — Interface `120001` (Midnight)                                   |
| **Dependencies**         | None                                                                     |
| **Optional**             | [Masque](https://www.curseforge.com/wow/addons/masque) for icon skinning |
| **Detected unit frames** | Blizzard default and raid-style party frames, ElvUI party frames         |
| **Saved variables**      | `HM_Position`, `HM_Settings` (per account)                               |

## Project structure

```text
HealerMana
├─ assets/                      -- Static resources
│  ├─ logo.png                  -- Branding
│  └─ sounds/                   -- Sound alert files (not yet wired up)
│     ├─ healerDrinking.mp3
│     └─ healerLowMana.mp3
├─ healermana.toc               -- Addon metadata and file load order
├─ healermana.lua               -- Core logic (healer tracking, frames, events)
└─ settings.lua                 -- In-game settings panel UI (/hms)
```

## Roadmap

<details>
<summary><b>Planned designs and features</b></summary>
<br>
<div align="center">

| Planned default party design                                                                                                                                     | Planned default raid design                                                        |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| <div align="left">- The icon will change if the healer is currently restoring mana or not. <br> - The NUM% part will change color based on the percentage.</div> | <div align="left">- The NUM% part will change color based on the percentage.</div> |
| <img src="assets/planned_party.png" width="50%"></img>                                                                                                           | <img src="assets/planned_raid.png" width="50%"></img>                              |

</div>
</details>

- Colour the mana percentage based on how low it is.
- Raid layout in addition to the party layout.
- Sound alerts for drinking and low mana (audio files are already in `assets/sounds/`).
- A `/hm reset` command to recentre the anchor without opening the panel.
- Additional fonts, including fonts shipped with ElvUI or other sources.

## Feedback

Bug reports, ideas, and pull requests are welcome. Open an
[issue](https://github.com/zsoltfrks/healer-mana/issues) or a
[pull request](https://github.com/zsoltfrks/healer-mana/pulls).
