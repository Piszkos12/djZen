# djZen

One-click "DJ Zen mode" for Windows laptops. Silences notifications, disables Wi-Fi/Bluetooth, USB power saving and resource-hungry background tasks that cause audio dropouts and DPC latency – then restores everything, even after a reboot. Custom profiles, DJ software descriptors. Free Pascal/Lazarus. Never touches security software.

> **Status:** early release (0.1, pre-release). Every tweak has passed a live apply/revert test,
> but djZen has not been used at real gigs yet. Test it at home first. Roadmap: [PLAN.md](PLAN.md).

## Download

**[Download the latest release](https://github.com/Piszkos12/djZen/releases/latest/download/djZen-win64.zip)**
· [all releases](https://github.com/Piszkos12/djZen/releases)
· [website](https://piszkos12.github.io/djZen/)

Unzip anywhere and run `djZen.exe` (Windows 10/11, 64-bit; asks for administrator rights).
djZen is not code-signed yet: Windows SmartScreen may warn ("More info → Run anyway"), and
Smart App Control blocks unsigned apps.

## Principles

- **Security software is never touched** – Defender, firewall, SmartScreen and antivirus are off-limits, even optionally. A built-in blocklist enforces this in code.
- **Everything is reversible** – the original state is saved before any change and survives crashes and reboots.
- **djZen itself stays out of the way** – no animations, no sounds, no background polling.
- **Native code only** – every tweak is Pascal code; no PowerShell or other scripts run with admin rights.
- **No hard-coded DJ software** – DJ apps are described by data-only JSON files anyone can add.

## What it changes

Options are grouped by how much they help a live set. Each row shows its current state
(OK / Needs change / N/A) and explains itself in the tooltip.

| Impact | Option | What it does |
|---|---|---|
| High | Turn off notifications | Toast notifications and their sounds off |
| High | Mute system sounds | Clears every Windows event sound, selects "No Sounds" |
| High | Disable USB selective suspend | Idle USB ports stay powered (controllers, audio interfaces) |
| High | Never sleep | No sleep during a set |
| High | Turn off Wi-Fi | Wi-Fi radio off (a top cause of DPC latency) |
| High | Pause Windows Update | Service stopped and disabled until restore |
| Medium | Disable communication ducking | Windows no longer lowers the volume on "calls" |
| Medium | Disable PCI Express power saving | Link State Power Management off (advanced) |
| Medium | Keep CPU at full speed | Minimum processor state 100% |
| Medium | Never turn off the display | Screen stays on |
| Medium | Turn off Bluetooth | Bluetooth radio off (via Windows radio management) |
| Medium | Pause search indexing | Windows Search service stopped |
| Medium | Raise DJ software priority | Selected DJ software gets "high" priority (never "realtime") |
| Low | Never hibernate | No automatic hibernation |
| Low | Pause SysMain (Superfetch) | Background preloading stopped |

Power settings are applied to the active power plan for both plugged-in and battery mode.

## Profiles

Built-in: **Offline zen** (everything off), **Streaming zen** (network stays on) and
**Home practice** (only the things that make sounds). Change any checkbox and save your own via
the **"..."** menu next to the profile list: save, save as new, delete, import, export.
User profiles live in `%APPDATA%\djZen\profiles\`. djZen remembers the last profile, DJ software
and unsaved changes.

## DJ software

Select your DJ software so djZen protects its processes and raises its priority. Built-in
descriptors: rekordbox, Serato DJ Pro/Lite, Traktor Pro, VirtualDJ, Mixxx, djay Pro (djay's
process name is not yet verified). Add or override one by dropping a JSON file into
`%APPDATA%\djZen\apps\`:

```json
{
  "id": "rekordbox",
  "name": "Pioneer DJ rekordbox",
  "processes": ["rekordbox.exe"],
  "priority": "high",
  "protectServices": [],
  "protectDevices": [],
  "needsNetwork": false,
  "notes": ""
}
```

`priority` is `normal`, `abovenormal` or `high`; `realtime` is rejected. With `needsNetwork`
djZen warns before switching Wi-Fi off. Descriptors are data only and can only add protection.
Corrections and new descriptors are welcome as pull requests to [apps/](apps/).

## Restore

- Press the button again (**ZEN ON – click to restore**).
- Closing djZen while Zen mode is active asks whether to restore first.
- If djZen crashed or the PC restarted while Zen mode was active, it offers to restore on the next start.
- From the command line, if djZen cannot be opened normally:

```
djZen.exe /restore          restore and show the result
djZen.exe /restore /quiet   restore silently (exit code 0 = OK, 1 = failures)
```

Files: snapshot and log in `%ProgramData%\djZen\` (`snapshot.json`, `logs\djzen.log`),
settings and user profiles in `%APPDATA%\djZen\`.

## Building

Requirements: [Lazarus](https://www.lazarus-ide.org/) 4.8 with FPC 3.2.2 (Win64). If Lazarus is
not in `D:\lazarus`, set `LAZARUS_DIR`.

```
build.bat     bin\dev\djZen.exe (debug) and bin\prod\djZen.exe (release), with apps\ and profiles\
clean.bat     removes bin\, lib\ and backup\
test.bat      builds and runs the unit tests
release.bat   build + tests + dist\djZen-win64.zip for a GitHub Release
```

## Testing

```
test.bat                                   unit tests (change nothing on the system)
set "DJZEN_LIVE_TESTS=1" && test.bat       + live round-trip test: really applies and reverts
                                             every tweak (elevated prompt required)
```

## Disclaimer

djZen changes system settings (power plans, services, devices, radios). **Use it at your own risk.**
It is provided "as is", without warranty of any kind, and the authors accept no liability for any
damage, data loss, failed performance or other consequence of using it. You alone decide whether to
use it — test it at home before relying on it live. See sections 15 and 16 of the [license](LICENSE).

## License

[GPL-3.0](LICENSE)
