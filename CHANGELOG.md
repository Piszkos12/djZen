# Changelog

## 0.1.1 – 2026-10-11

Security release: djZen no longer runs everything as administrator.

- **Privilege separation:** djZen runs as the normal user. Only the three service options
  (Windows Update, Search, SysMain, marked "(admin)") use a small elevated helper, started
  through UAC once when Zen mode starts and once when it is restored. Profiles without admin
  options need no administrator rights at all.
- **Admin data folder hardened:** `%ProgramData%\djZen` gets a protected ACL (only
  Administrators/SYSTEM can write; before, any user could create files there), junctions and
  symlinks are never followed, and files not owned by Administrators/SYSTEM are ignored.
- **DLL loading hardened:** DLLs are loaded from System32 only; `powrprof.dll` is no longer a
  static import. djZen refuses to elevate while any `.dll` file is next to `djZen.exe`.
- **Release zip contains a `djZen` folder**, so even "extract here" in Downloads gives djZen its
  own folder.
- User snapshot, log and lock file moved to `%LOCALAPPDATA%\djZen\`; notification and sound
  settings now always change the logged-on user, also when another account confirms UAC.
- The single-instance lock is per logon session (`Local\` mutex).
- Build: all compiler hints and warnings fixed; `test.bat` renamed to `tests.bat`; the live
  test also runs from a normal prompt and lists which options need admin rights.

**Upgrading while Zen mode is active:** restore with 0.1.0 first, then switch to 0.1.1
(the snapshot location and format changed).

## 0.1.0 – 2026-10-11

First public pre-release.

- One-click Zen mode with 15 options: notifications, system sounds, call ducking, USB selective
  suspend, sleep, PCIe power saving, CPU minimum state, display off, hibernate, Wi-Fi,
  Bluetooth, Windows Update, Search, SysMain, DJ software priority.
- Built-in profiles (Offline zen, Streaming zen, Home practice) and user profiles (save, delete,
  import, export).
- DJ software descriptors: rekordbox, Serato DJ, Traktor, VirtualDJ, Mixxx, djay Pro.
- Full restore, also after a crash or reboot; `djZen.exe /restore`.
- Security software is never touched.
