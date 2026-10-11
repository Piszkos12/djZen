# djZen

One-click "DJ Zen mode" for Windows laptops. Silences notifications, disables Wi-Fi/Bluetooth, USB power saving and resource-hungry background tasks that cause audio dropouts and DPC latency – then restores everything, even after a reboot. Custom profiles, per-DJ-app scripts. Free Pascal/Lazarus. Never touches security software.

> **Status:** early development – not usable yet. See [PLAN.md](PLAN.md) (Hungarian) for the roadmap.

## Principles

- **Security software is never touched** – Defender, firewall, SmartScreen and antivirus are off-limits, even optionally.
- **Everything is reversible** – a snapshot of the original state is saved before any change and survives reboots.
- **djZen itself stays out of the way** – minimal CPU and memory use while Zen mode is active.
- **No hard-coded DJ software** – DJ apps are described by separate, community-editable files.

## Building

Requirements: [Lazarus](https://www.lazarus-ide.org/) 4.8 with FPC 3.2.2 (Win64).

```
lazbuild djZen.lpi
```

The executable is written to `bin\djZen.exe` and requires administrator rights.

## Emergency restore

If djZen cannot be opened normally, restore every changed setting from the command line:

```
djZen.exe /restore          restore and show the result
djZen.exe /restore /quiet   restore silently (exit code 0 = OK, 1 = failures)
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
