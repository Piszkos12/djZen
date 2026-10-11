# djZen – Projektterv

> Egy gombos „DJ Zen mód” Windows laptopokhoz: kikapcsolja és felügyeli mindazt, ami
> élő DJ-zés közben belebeszélhet a hangba, elveheti az erőforrást vagy mikroakadást okozhat –
> és mindent pontosan visszaállít.

- **Nyelv / UI:** Free Pascal + Lazarus (LCL), natív Win32 GUI
- **Platform:** Windows 10 / 11 (x64)
- **Licenc:** nyílt forráskódú, publikus repo (licenc: GPL-3.0)
- **Jogosultság:** rendszergazdai (manifest: `requireAdministrator`)

---

## 1. Alapelvek (nem alku tárgya)

1. **Biztonsági szoftverhez SOHA nem nyúlunk.** Windows Defender, tűzfal, SmartScreen,
   harmadik féltől származó vírusirtó, ezek szolgáltatásai, ütemezett feladatai, értesítései –
   még opcionálisan, még felhasználói profilból sem. Ezt a mag kódszinten tiltja (beépített
   tiltólista, amit profil/script nem írhat felül).
2. **Minden visszaállítható.** Zen mód bekapcsolásakor pillanatkép (snapshot) készül az összes
   érintett beállítás eredeti állapotáról, lemezre mentve. A kikapcsolás újraindítás, összeomlás
   vagy áramszünet után is működik.
3. **A djZen maga sem zavarhat.** Zen módban minimális CPU/memória, nincs aktív polling
   szükségtelenül, nincs animáció, nincs felugró ablak, nincs hang. A watchdog alacsony
   prioritású szálon, ritka (pl. 2–5 s) ciklussal fut. Mérjük és dokumentáljuk a saját
   terhelését.
4. **Nincs bedrótozott DJ-szoftver.** A DJ-alkalmazásokat külön leíró fájlok (scriptek) írják
   le, a közösség bővítheti őket.
5. **Átlátható.** Minden lépés naplózva, a felhasználó előre látja, mit fog módosítani a program.
6. **Védett elemek.** Az audio alapszolgáltatások (`Audiosrv`, `AudioEndpointBuilder`), a
   kiválasztott DJ-szoftver, a hangkártya/kontroller driverei és azok szolgáltatásai sosem
   kerülnek leállításra.

---

## 2. Zavaró tényezők katalógusa

Minden tétel egy **„tweak”**: `Check` (állapot lekérdezése) / `Apply` (alkalmazás) /
`Revert` (visszaállítás snapshotból). A tételek kockázati szintet kapnak: *biztonságos* /
*haladó* / *szakértő*.

### 2.1 Hangba belebeszélő dolgok
- Értesítések: Focus Assist / „Ne zavarjanak” bekapcsolása
- Rendszerhangséma → „Nincs hang” (eredeti séma mentése)
- Kommunikációs ducking („Hívás közben csökkentse a hangerőt”) → „Ne tegyen semmit”
- Windows Update újraindítási értesítések elhalasztása (aktív órák kiterjesztése)
- Audio „enhancement”-ek jelzése (Realtek, Nahimic, Dolby, Sonic Studio) – audit, opcionális tiltás
- Alapértelmezett lejátszóeszköz rögzítése és figyelése (HDMI / BT eszköz ne vegye át)
- Kommunikációs appok (Teams, Discord, Skype, Outlook) bezárása – profilfüggő

### 2.2 Mikroakadások (DPC/ISR latencia)
- WiFi adapter letiltása (rádió vagy eszköz szinten)
- Bluetooth letiltása
- ACPI akkumulátor-eszköz (Microsoft ACPI-Compliant Control Method Battery) – *szakértő*, csak hálózati tápon, figyelmeztetéssel
- Hálózati adapter energiatakarékosság és megszakítás-moderálás – *haladó*
- Webkamera, ujjlenyomat-olvasó, egyéb nem használt eszközök letiltása – profilban választható
- GPU energiaállapot (pl. NVIDIA „Prefer maximum performance”) – *haladó*, audit elsőként

### 2.3 Energiagazdálkodás
- Saját „djZen” energiaséma létrehozása és aktiválása (eredeti séma GUID mentése)
- USB Selective Suspend → tiltva
- Eszközönkénti „A számítógép kikapcsolhatja az eszközt” → tiltva (USB hubok, kontroller, audio interfész)
- PCIe Link State Power Management → Ki
- Processzor min. állapot 100%, core parking ki, EPP teljesítmény
- Alvás, hibernálás, kijelző kikapcsolás, képernyővédő → tiltva
- Akkus üzem figyelése, figyelmeztetés
- Megjegyzés: CPU C-state-ek teljes tiltása csak BIOS-ból – csak tanácsként jelenítjük meg

### 2.4 Erőforrásfaló háttérfolyamatok és szolgáltatások
- Windows Update szolgáltatás szüneteltetése (pause API), Delivery Optimization, BITS
- Windows Search indexelő szüneteltetése
- SysMain (Superfetch)
- Telemetria (DiagTrack)
- Ütemezett karbantartás, defrag/optimize
- Felhőszinkron: OneDrive, Dropbox, Google Drive – szüneteltetés/bezárás
- Launcherek, overlay-ek: Steam, Epic, Xbox Game Bar, GeForce Experience, Adobe CC
- Böngészők – profilfüggő (streamingnél kellhet)
- **Kivétel:** Defender és minden biztonsági komponens – lásd 1.1

### 2.5 Hálózat és rádiók
- WiFi, Bluetooth, Ethernet, mobilnet, NFC – egyenként kapcsolható
- Repülőgép üzemmód
- Profilban felülírható (pl. streaming, BT fejhallgató, WiFi-s okostelefon kontroller)

### 2.6 Egyéb
- DJ-szoftver folyamatprioritása (High; Realtime soha)
- Fókuszlopás és felugró ablakok csökkentése
- Automatikus fényerő, adaptív kontraszt, Night Light – profilfüggő
- Időzítő felbontás – audit

---

## 3. Profilok

- **Beépített profilok** (csak olvasható, másolható):
  - **Offline gig** – maximális tiltás, nincs hálózat
  - **Streaming gig** – hálózat marad, minden más tiltva
  - **Otthoni gyakorlás** – enyhébb, csak a hangot zavaró dolgok
- **Felhasználói profilok:** beépítettből másolva vagy nulláról, GUI-ban szerkeszthető
  (pl. „WiFi és BT marad, mert a kontrollerem BT-s”).
- Formátum: JSON, helye `%APPDATA%\djZen\profiles\`.
- A profil egy tweak-azonosító → beállítás lista + a hozzárendelt DJ-szoftver script(ek).
- Import / export a közösségi megosztáshoz.

---

## 4. DJ-szoftver leírók („scriptek”)

Deklaratív leíró fájl DJ-alkalmazásonként, nem bedrótozott kód. Helye: `apps\*.json`
(beépített) és `%APPDATA%\djZen\apps\` (felhasználói).

Tartalom (tervezet):
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
- Kezdő készlet: rekordbox, Serato DJ, Traktor, VirtualDJ, Mixxx, djay Pro
- Később mérlegelendő: valódi scriptnyelv (pl. Pascal Script) – csak ha a deklaratív forma kevés.

---

## 5. Pillanatkép (snapshot) és visszaállítás

- Zen mód bekapcsolásakor **minden módosítás előtt** mentés az eredeti értékről
  (`%ProgramData%\djZen\snapshot.json`), atomikus írással (temp fájl + átnevezés).
- A snapshot lépésenként frissül, így félbeszakadt bekapcsolás is visszaállítható.
- Indításkor: ha létezik aktív snapshot, a program felajánlja a visszaállítást vagy a folytatást.
- Opcionális: újraindítás után automatikus felajánlás (ütemezett feladat / Run kulcs).
- Visszaállítás fordított sorrendben; sikertelen tétel naplózva, a többi folytatódik.
- Végső mentőöv: „Vészhelyzeti visszaállítás” parancssori kapcsoló (`djZen.exe /restore`).

---

## 6. Watchdog (felügyelet Zen módban)

- Visszakapcsolt-e valami (szolgáltatás, rádió, folyamat, energiaséma) → újra alkalmaz vagy jelez
- Audioeszköz / kontroller jelenléte → azonnali, feltűnő, de **hangtalan** jelzés
- Tápellátás (akku / hálózat), töltöttség
- CPU-terhelés, throttling jelzése
- Később: egyszerű időzítő-jitter / DPC-latencia mérés
- Saját erőforrás-korlát: alacsony prioritású szál, ritka ciklus, eseményvezérelt, ahol lehet
  (`WM_DEVICECHANGE`, `WM_POWERBROADCAST`, szolgáltatás-értesítések)

---

## 7. Felhasználói felület

- Főablak: nagy **ZEN BE / KI** gomb, profilválasztó, állapotjelző (zöld/sárga/piros)
- Audit nézet: tételenkénti állapot, kockázati szint, magyarázat
- Előnézet: mi fog változni bekapcsolás előtt
- Profilszerkesztő, DJ-szoftver kezelő
- Tálcaikon minimális menüvel
- Zen módban: sötét, nyugodt, statikus felület – nincs animáció, nincs felugró ablak
- Lokalizáció: magyar és angol (később bővíthető)

---

## 8. Architektúra (vázlat)

```
djZen/
├─ src/
│  ├─ core/         tweak alaposztály, regisztráció, snapshot, napló, tiltólista
│  ├─ tweaks/       egy unit kategóriánként (power, radio, services, audio, process, ...)
│  ├─ platform/     Win32 / SetupAPI / WMI / COM / powrprof wrapper unitok
│  ├─ profiles/     profil betöltés, mentés, validálás
│  ├─ apps/         DJ-szoftver leírók kezelése
│  ├─ watchdog/
│  └─ ui/           Lazarus formok
├─ apps/            beépített DJ-szoftver leírók (JSON)
├─ profiles/        beépített profilok (JSON)
├─ docs/
├─ tests/           fpcunit
└─ PLAN.md
```

Alapinterfész (tervezet):
```pascal
TTweak = class
  function Id: string; virtual; abstract;
  function Category: TTweakCategory; virtual; abstract;
  function Risk: TTweakRisk; virtual; abstract;
  function Check: TTweakState; virtual; abstract;
  function Capture: TJSONObject; virtual; abstract;   // eredeti állapot a snapshotba
  procedure Apply(Params: TJSONObject); virtual; abstract;
  procedure Revert(Saved: TJSONObject); virtual; abstract;
end;
```

---

## 9. Ütemterv (mérföldkövek)

1. **M0 – Projektváz:** repo, Lazarus projekt, mappaszerkezet, licenc, README, build
2. **M1 – Mag:** `TTweak`, regisztráció, napló, tiltólista, snapshot
3. **M2 – Audit mód:** az összes tétel `Check`-je, GUI audit nézet (csak olvas, nem módosít)
4. **M3 – Apply/Revert:** „biztonságos” szintű tételek, beépített profilok, újraindítás utáni visszaállítás
5. **M4 – Profilszerkesztő és DJ-szoftver leírók**
6. **M5 – Watchdog, tálcaikon**
7. **M6 – Haladó/szakértő tételek, latenciamérés, lokalizáció, telepítő**

---

## 10. Nyitott kérdések

- Telepítő (Inno Setup) vagy portable exe – vagy mindkettő?
- Lazarus verzió / minimálisan támogatott Windows build
- Snapshot automatikus felajánlása újraindítás után: ütemezett feladat vagy Run kulcs?
