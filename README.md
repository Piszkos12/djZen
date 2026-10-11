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

## License

[GPL-3.0](LICENSE)
