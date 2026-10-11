# djZen – Project Plan

> One-click "DJ Zen mode" for Windows laptops: switches off and monitors everything that can
> talk into the audio, steal resources or cause micro-dropouts during a live DJ set – and
> restores everything exactly as it was.

- **Language / UI:** Free Pascal + Lazarus (LCL), native Win32 GUI
- **Platform:** Windows 10 / 11 (x64)
- **License:** open source, public repo, GPL-3.0
- **Privileges:** administrator (manifest: `requireAdministrator`)
- **Liability:** none. Users decide for themselves whether to use djZen; it is provided "as is"
  (see README and GPL-3.0 sections 15–16).

---

## 1. Principles (non-negotiable)

1. **Security software is NEVER touched.** Windows Defender, firewall, SmartScreen,
   third-party antivirus, their services, scheduled tasks and notifications – not even
   optionally, not even from a user profile. Enforced in code by a built-in blocklist that no
   profile or descriptor can override.
2. **Everything is reversible.** When Zen mode is switched on, a snapshot of the original state
   of every affected setting is saved to disk. Switching off works after a reboot, crash or
   power loss.
3. **djZen itself must not get in the way.** Minimal CPU and memory in Zen mode, no needless
   polling, no animations, no pop-ups, no sounds. The watchdog runs on a low-priority thread
   with a slow cycle (e.g. 2–5 s). Its own load is measured and documented.
4. **Every tweak is native Pascal code.** No PowerShell or other external scripts in tweaks:
   this way the blocklist can be enforced for every operation, and no admin-level code runs
   from user-writable files. A new tweak means a new program release.
5. **No hard-coded DJ software.** DJ applications are described by separate descriptor files
   (data only, no executable actions) that the community can extend.
6. **Transparent.** Every step is logged; the user sees in advance what will change.
7. **Protected items.** Core audio services (`Audiosrv`, `AudioEndpointBuilder`), the selected
   DJ software, the audio interface / controller drivers and their services are never stopped.

---

## 2. Catalogue of disruptions

Each item is a **tweak**: `Check` (read state) / `Capture` (save original) / `Apply` /
`Revert` (restore from snapshot). Every tweak has an **impact** (High / Medium / Low – how much
it helps a live set; the UI groups options by it) and a **risk** level (Safe / Advanced /
Expert).

### 2.1 Things that talk into the audio
- Notifications: toasts off, Focus Assist / Do Not Disturb
- System sound scheme → "No Sounds" (original scheme saved)
- Communication ducking ("reduce other sounds during calls") → "Do nothing"
- Postpone Windows Update restart notifications (extend active hours)
- Flag audio "enhancements" (Realtek, Nahimic, Dolby, Sonic Studio) – audit, optional disable
- Pin and watch the default playback device (HDMI / Bluetooth devices must not take over)
- Close communication apps (Teams, Discord, Skype, Outlook) – per profile

### 2.2 Micro-dropouts (DPC/ISR latency)
- Disable the Wi-Fi adapter (radio or device level)
- Disable Bluetooth
- ACPI battery device (Microsoft ACPI-Compliant Control Method Battery) – *expert*, only on AC power, with a warning
- Network adapter power saving and interrupt moderation – *advanced*
- Disable webcam, fingerprint reader and other unused devices – selectable per profile
- GPU power state (e.g. NVIDIA "Prefer maximum performance") – *advanced*, audit first

### 2.3 Power management
- Create and activate a dedicated "djZen" power plan (original plan GUID saved)
- USB selective suspend → disabled
- Per-device "Allow the computer to turn off this device" → off (USB hubs, controller, audio interface)
- PCIe Link State Power Management → off
- Minimum processor state 100%, core parking off, EPP performance
- Sleep, hibernate, display off, screen saver → disabled
- Watch battery operation and warn
- Note: fully disabling CPU C-states is only possible in the BIOS – shown as advice only

### 2.4 Resource-hungry background processes and services
- Pause Windows Update (pause API), Delivery Optimization, BITS
- Pause Windows Search indexing
- SysMain (Superfetch)
- Telemetry (DiagTrack)
- Scheduled maintenance, defrag/optimize
- Cloud sync: OneDrive, Dropbox, Google Drive – pause/close
- Launchers and overlays: Steam, Epic, Xbox Game Bar, GeForce Experience, Adobe CC
- Browsers – per profile (may be needed for streaming)
- **Exception:** Defender and every security component – see principle 1

### 2.5 Network and radios
- Wi-Fi, Bluetooth, Ethernet, mobile broadband, NFC – individually switchable
- Airplane mode
- Can be overridden per profile (e.g. streaming, BT headphones, Wi-Fi phone controller)

### 2.6 Other
- DJ software process priority (High; never Realtime)
- Reduce focus stealing and pop-up windows
- Auto brightness, adaptive contrast, Night Light – per profile
- Timer resolution – audit

---

## 3. Profiles

- **Built-in profiles** (read-only, can be copied):
  - **Offline zen** – maximum lockdown, no network
  - **Streaming zen** – network stays, everything else off
  - **Home practice** – lighter, only the things that make sounds
- **User profiles:** copied from a built-in one or created from scratch, editable in the GUI
  (e.g. "keep Wi-Fi and Bluetooth, my controller is Bluetooth").
- Format: JSON, stored in `%APPDATA%\djZen\profiles\`.
- A profile is a list of tweak id → setting, plus the assigned DJ software descriptor(s).
- Import / export for community sharing.

---

## 4. DJ software descriptors

One declarative descriptor file per DJ application, no hard-coded logic. Location: `apps\*.json`
(built-in) and `%APPDATA%\djZen\apps\` (user).

Content (draft):
```json
{
  "id": "rekordbox",
  "name": "Pioneer rekordbox",
  "processes": ["rekordbox.exe"],
  "priority": "high",
  "protectServices": ["PioneerDJ*"],
  "protectDevices": ["USB\\VID_2B73*"],
  "needsNetwork": false,
  "notes": "..."
}
```
- Initial set: rekordbox, Serato DJ, Traktor, VirtualDJ, Mixxx, djay Pro
- Descriptors contain data only; an executable script language is deliberately not supported
  (see principle 4).

---

## 5. Snapshot and restore

- When Zen mode is switched on, the original value is saved **before every change**
  (`%ProgramData%\djZen\snapshot.json`) with atomic writes (temp file + MoveFileEx write-through).
- The snapshot is updated step by step, so an interrupted activation can still be reverted.
- On start-up: if an active snapshot exists, the program offers to restore or continue.
- Optional: offer the restore automatically after a reboot (scheduled task / Run key).
- Restore runs in reverse order; a failed item is logged and kept for retry, the rest continues.
- Last resort: an emergency restore command-line switch (`djZen.exe /restore`).

---

## 6. Watchdog (monitoring in Zen mode)

- Has anything switched back on (service, radio, process, power plan)? → re-apply or report
- Audio device / controller presence → immediate, prominent but **silent** alert
- Power source (battery / AC), charge level
- CPU load, throttling
- Later: simple timer-jitter / DPC latency measurement
- Own resource budget: low-priority thread, slow cycle, event-driven where possible
  (`WM_DEVICECHANGE`, `WM_POWERBROADCAST`, service notifications)

---

## 7. User interface

- Main window: big **ZEN ON / OFF** button, profile selector, status indicator (green/yellow/red)
- Zen options as checkboxes, **grouped by impact** (High / Medium / Low impact), with a
  colored audit status per row; risk level and description in the tooltip
- Preview: what will change before switching on
- Profile editor, DJ software manager
- Tray icon with a minimal menu
- In Zen mode: dark, calm, static UI – no animations, no pop-ups
- Visible disclaimer ("use at your own risk")
- Localization: English first (Hungarian and others later)

---

## 8. Architecture

```
djZen/
├─ src/
│  ├─ core/         tweak base class, registry, engine, snapshot, log, blocklist, paths
│  ├─ tweaks/       one unit per area (power, radio, services, notify, ...)
│  ├─ platform/     Win32 / SetupAPI / WMI / COM / powrprof wrapper units
│  ├─ profiles/     profile load, save, validation
│  ├─ apps/         DJ software descriptor handling
│  ├─ watchdog/
│  └─ ui/           Lazarus forms
├─ apps/            built-in DJ software descriptors (JSON)
├─ profiles/        built-in profiles (JSON)
├─ docs/
├─ tests/           fpcunit tests
├─ build.bat        builds dev + prod into bin\dev and bin\prod
├─ clean.bat        removes build output
├─ test.bat         builds and runs the unit tests
└─ PLAN.md
```

Core interface:
```pascal
TTweak = class
  function Id: string;                  // stable, used in profiles and snapshots
  function Name, Description: string;
  function Category: TTweakCategory;
  function Impact: TTweakImpact;        // UI grouping
  function Risk: TTweakRisk;
  function CanApply: Boolean;           // False for audit-only tweaks
  function Check: TTweakCheck;          // read-only status + detail
  function Capture: TJSONObject;        // original state for the snapshot
  procedure Apply(Params: TJSONObject);
  procedure Revert(Saved: TJSONObject);
end;
```

---

## 9. Milestones

1. **M0 – Project skeleton** ✅ repo, Lazarus project, folder layout, license, README, build scripts
2. **M1 – Core** ✅ `TTweak`, registry, engine, log, blocklist, snapshot, unit tests
3. **M2 – Audit mode** ✅ `Check`/`Capture` for the first tweaks (power, radios, notifications,
   services), GUI with impact groups and colored status (read-only, changes nothing)
4. **M3 – Apply/Revert** ✅ power, notification/sound, service and Wi-Fi tweaks, built-in profiles,
   restore after reboot, `/restore` switch, opt-in live round-trip test, Bluetooth via
   Windows radio management (WinRT)
5. **M4 – Profile editor and DJ software descriptors**
6. **M5 – Watchdog, tray icon**
7. **M6 – Advanced/expert tweaks, latency measurement, localization, installer**

---

## 10. Open questions

- Installer (Inno Setup), portable exe – or both?
- Minimum supported Windows build
- Automatic restore offer after reboot: scheduled task or Run key?
- HKCU settings when a standard user elevates with another account's credentials
