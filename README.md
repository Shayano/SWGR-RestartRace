# SWGR Restart Race and Skip Intros

Two independent UE4SS Lua mods for **STAR WARS Galactic Racer** (PC):

- **Restart Race** adds a "Restart Race" button to the campaign pause menu. Restarting puts the
  run back the way it was when the race started.
- **Skip Intros** skips the startup logos (Fuse Games, Secret Mode, Lucasfilm).

Version française : [LISEZMOI.md](LISEZMOI.md).

Tested on 2026-10-26 with the Steam version of the game (build 26133805) and
UE4SS Galactic Racer Edition 0.9.4.

## Requirements

[UE4SS Galactic Racer Edition](https://www.nexusmods.com/starwarsgalacticracer/mods/2), installed
in `STAR WARS Galactic Racer\Griffin\Binaries\Win64` (the folder containing
`SWGR-Win64-Shipping.exe`).

## Install

1. Close the game.
2. Download `RestartRace.zip` and/or `SkipIntros.zip` from the
   [Releases](../../releases) page.
3. Extract them **directly into the `Win64` folder** above. Files must end up in:
   - `Win64\ue4ss\Mods\RestartRace\` (`enabled.txt`, `config.lua`, `Scripts\main.lua`)
   - `Win64\ue4ss\Mods\SkipIntros\` (`enabled.txt`, `Scripts\main.lua`)
4. Start the game.

To check that the mods are loaded, open `Win64\ue4ss\UE4SS.log`: it should contain
`[RestartRace] Loaded` and `[SkipIntros] Loaded`.

## Uninstall

Delete the mod folder from `Win64\ue4ss\Mods\`. To disable a mod without deleting it, rename its
`enabled.txt` (to `enabled.txt.off` for instance).

## Restart Race

### How it works

- The button appears right below "Resume", **only during a campaign race that can be
  restarted**. It is hidden during event selection, after the finish line and outside the
  campaign (arcade modes already have their own retry button).
- It works with a gamepad, keyboard or mouse.
- When a race starts, the mod records the parts of the run a race can change. Restarting puts
  them back before travelling: credits from before the side bet, vehicle health, strikes, faulty
  parts and the event generation seed (so you get the same track again).
- If the campaign is not at the start of an event when you click, the restart is cancelled
  without changing anything and the race goes on. The log then says `Restart cancelled`.

### Settings (`config.lua`)

| Option | Effect |
|---|---|
| `label`, `description` | Button text and description. `nil` follows the game language (English or French). |
| `restore_run_state` | `true` puts the run back to its race start state. `false` only restarts. |
| `debug` | `true` logs every restart in detail in `UE4SS.log` (credits, health, parts, track). |

### Verified in game

- The button shows up immediately and the menu stays usable, with a gamepad or a mouse.
- The race restarts from the beginning, on the same track, many times in a row.
- A part that broke during the race is repaired on restart.

**Not verified yet**:

- the side bet refund (no race with a bet during testing);
- keeping the same track when a part broke during the race. In v1.0.0 that case could land on
  another track; v1.1.0 applies the pending fault before restoring the run, which should fix it.

With `debug = true`, the log shows the credits, parts and track before and after each restart.
Reports are welcome in the issues.

## Skip Intros

The game menu plays `MEDIA_Intro_FUSE_Ident.bk2` then `MEDIA_Intro_Brand_Ident.bk2` and waits for
each one to end. The mod moves playback to the end of the video as soon as it starts, so the
game gets its normal "video finished" event and carries on. The EULA, photosensitivity warning
and "press any key" screens are untouched. No game file is modified.

## Why a rewrite

These mods started from issues found in Restart Race 2.0 on Nexus:

- the restart used `TravelToStartOrContinueCampaign` without restoring anything: side bets were
  lost, part damage stayed, and sometimes the track changed;
- the side bet refund watched for credits dropping *after* the restart, while the bet is paid
  before it;
- the button was inserted once per second by rebuilding the menu, which could freeze the pause
  menu if you navigated too early;
- gamepad clicks were not detected reliably;
- `config.lua` was never read, and the zip used `\` path separators.

The code here is an independent implementation. Credit to GenerousMods for the original idea of a
restart button for this game.

## Troubleshooting

- **Nothing happens**: check `Win64\ue4ss\UE4SS.log`. If it does not exist, UE4SS is not loading
  or cannot write to its folder (Properties, Security, allow write access).
- **After a game update**: update UE4SS Galactic Racer Edition first.
- **Saves**: `%LOCALAPPDATA%\StarWarsGalacticRacer\Saved\SaveGames\`. Back them up before trying
  any mod.

## License

[MIT](LICENSE). Not affiliated with Fuse Games, Secret Mode, Lucasfilm or Disney. STAR WARS is a
trademark of Lucasfilm Ltd.
