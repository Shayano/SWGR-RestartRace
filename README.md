# SWGR Restart Race and Skip Intros

Two independent UE4SS Lua mods for **STAR WARS Galactic Racer** (PC):

- **Restart Race** adds a "Restart Race" button to the campaign pause menu. Restarting puts the
  run back the way it was when the race started.
- **Skip Intros** skips the startup logos (Fuse Games, Secret Mode, Lucasfilm).

Version française : [LISEZMOI.md](LISEZMOI.md).

Tested on 2026-10-26 on Windows with the Steam version of the game (build 26133805) and
UE4SS Galactic Racer Edition 0.9.4, then on 2026-10-29 on Linux with Proton.

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

## Linux (Proton)

The mods work under Proton, but UE4SS needs one launch option. UE4SS is loaded through the
`dwmapi.dll` file in the `Win64` folder, and Wine uses its own copy of that DLL unless told
otherwise. In Steam, right-click the game, then Properties, General, Launch options:

```
WINEDLLOVERRIDES="dwmapi=n,b" %command%
```

Without it, the game starts normally but `UE4SS.log` is not updated and the mods do nothing.

- The game folder is in your Steam library, under
  `steamapps/common/STAR WARS Galactic Racer/Griffin/Binaries/Win64`. Install the mods there as
  described above.
- Under Wine, the times in `UE4SS.log` are in UTC.
- Saves are in the Proton prefix, under
  `steamapps/compatdata/4078430/pfx/drive_c/users/steamuser/AppData/Local/StarWarsGalacticRacer/Saved/SaveGames/`
  in your Steam folder (`~/.local/share/Steam/` by default).

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
  parts, the event generation seed and the other values of the run (so you usually get the same
  track again).
- If the restarted race still lands on another track, the mod restarts again, up to twice
  (`retry_if_track_changes`). If the track is still different after that, the race goes on with
  the new track and the log says `Track still different`.
- If the campaign is not at the start of an event when you click, the restart is cancelled
  without changing anything and the race goes on. The log then says `Restart cancelled`.

### Settings (`config.lua`)

| Option | Effect |
|---|---|
| `label`, `description` | Button text and description. `nil` follows the game language (English or French). |
| `restore_run_state` | `true` puts the run back to its race start state. `false` only restarts. |
| `retry_if_track_changes` | `true` restarts again, up to twice, when the restarted race lands on another track. `false` keeps the new track. |
| `debug` | `true` logs every restart in detail in `UE4SS.log` (credits, health, parts, track). |

### Verified in game

- The button shows up immediately and the menu stays usable, with a gamepad or a mouse.
- The race restarts from the beginning, on the same track, many times in a row.
- The side bet is refunded on restart.
- A part that broke during the race is repaired on restart, and the race stays on the same track.
- Restarting also works in races that have no campaign map node, such as the first race of a
  run.

**Known issue**: on some map nodes, the game picks a different track each time it regenerates the
race, even though the mod puts back the same run state before each restart. On 2026-10-29, on an
Act 2 node, the first restart and both automatic restarts each landed on another track. The cause
is not found yet.

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
  or cannot write to its folder (Properties, Security, allow write access). On Linux, check the
  launch option (see [Linux (Proton)](#linux-proton)).
- **The game crashes while a race loads** (`Crashdump written to ...\ue4ss\crash_*.dmp`): v1.1.0
  and earlier crash in races that have no campaign map node, such as the first race of a run.
  This is fixed after v1.1.0: until the next release, replace `Scripts\main.lua` with the one from
  this repository.
- **After a game update**: update UE4SS Galactic Racer Edition first.
- **Saves**: `%LOCALAPPDATA%\StarWarsGalacticRacer\Saved\SaveGames\` on Windows (Linux: see
  [Linux (Proton)](#linux-proton)). Back them up before trying any mod.

## License

[MIT](LICENSE). Not affiliated with Fuse Games, Secret Mode, Lucasfilm or Disney. STAR WARS is a
trademark of Lucasfilm Ltd.
