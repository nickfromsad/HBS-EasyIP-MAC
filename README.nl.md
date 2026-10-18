# HBS // EasyIP MAC

[English](README.md) · **Nederlands**

<img src="docs/icon.png" width="128" alt="HBS EasyIP MAC icoon" align="right">

Vind Panasonic PTZ-camera's op het netwerk en verander hun IP-adres, vanaf een Mac. Een macOS-alternatief
voor Panasonics *EasyIP Setup Tool Plus*, die alleen voor Windows bestaat. Gemaakt voor broadcastklussen
waar je op een rig inprikt en snel wilt weten waar de domes zitten, ook als ze in een ander subnet staan.

Onderdeel van de HBS-tools van [Hof Broadcast Services](https://hofbroadcast.nl), naast de
[HBS – ATEM Auto Switcher](https://github.com/nickfromsad/HBS---Atem-Auto-Switcher).

---

## Wat het doet

Panasonic-camera's spreken een klein UDP-broadcastprotocol: *Easy IP*. Elke camera op dezelfde kabel,
switch of VLAN reageert op een zoekopdracht, **welk IP-adres of subnet hij ook heeft**. Deze app stuurt die
zoekopdracht tegelijk over alle netwerkpoorten van je Mac, laat elke camera zien die antwoordt, en kan een
camera een nieuw adres geven. De camera wordt daarbij op zijn MAC-adres aangesproken, dus dat werkt ook als
hij via gewoon IP onbereikbaar is.

---

## Functies

- **Vindt elke camera.** AW-UE150, HE130, UE100, HE40… en AW-RP-bedieningspanelen, in elk subnet
- **Alle netwerkpoorten tegelijk.** Wifi, USB-/Thunderbolt-ethernet, docks
- **Status per camera**: `OK` bereikbaar vanaf deze Mac · `SUBNET` in een ander subnet · `DUP IP` dubbel adres
- **Network Settings**: IP-adres, subnetmasker, gateway, DNS en HTTP-poort wijzigen
- **Join Subnet**: geef je Mac een extra IP-adres in het subnet van een camera en open de webinterface,
  **zonder iets aan de camera of de rig te veranderen**
- **Naar mijn subnet**: met één klik een vrij adres in het subnet van je Mac invullen
- **Auto IP**: een reeks nieuwe camera's (die standaard allemaal op `192.168.0.10` staan) opeenvolgende adressen geven
- **Webinterface**: dubbelklik op een camera om hem in de browser te openen
- **Automatisch zoeken**: blijft om de paar seconden zoeken en meldt camera's die aan gaan of wegvallen
- **Easy IP `OPEN` / `LOCKED`** (beta): laat zien of een camera nog wijzigingen accepteert (zie de 20-minutenregel)
- **Log**: elke zoekopdracht, wijziging en fout met tijd
- **Updatemelding**: in de kopbalk staat het als er een nieuwere versie op GitHub staat
- **Terminalcommando `easyip`** meegeleverd, voor scripts of een snelle check vanuit Terminal

Getest met de AW-UE150, AW-HE130 en het AW-RP120-bedieningspaneel.

---

## Downloaden

Download `HBS-EasyIP-MAC-x.y.z.dmg` bij de [nieuwste release](https://github.com/nickfromsad/HBS-EasyIP-MAC/releases/latest),
open hem en sleep **HBS EasyIP MAC** naar de map Programma's. Werkt op macOS 14 (Sonoma) of nieuwer, met
Apple Silicon of Intel.

**De eerste keer openen.** De app is (nog) niet door Apple gecontroleerd, dus macOS blokkeert hem de eerste
keer. Ga naar **Systeeminstellingen → Privacy en beveiliging**, scrol omlaag en klik op **Open toch**. Of voer
één keer dit uit in Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/HBS EasyIP MAC.app"
```

Als macOS erom vraagt, **sta toegang tot het lokale netwerk toe**. Anders worden er geen camera's gevonden
(in het log staat dan *No route to host*).

---

## Gebruik

1. Sluit de Mac aan op het cameranetwerk (welk IP-adres de Mac heeft maakt niet uit).
2. Open **HBS EasyIP MAC**. Hij zoekt meteen, en met **SEARCH CAMERAS** (⌘R) zoek je opnieuw.
3. Selecteer een camera en klik op **Network Settings…**, of selecteer er meerdere en klik op **Auto IP…**.
4. **Apply** verstuurt de nieuwe instellingen. De camera bevestigt, en een paar seconden later wordt de lijst ververst.

### Join Subnet: bij een camera komen zonder hem te veranderen

Een camera in een ander subnet (label `SUBNET`) kun je vanaf je Mac niet bereiken. In plaats van het IP van
de camera te veranderen, selecteer je hem en klik je op **Join Subnet…** (of je dubbelklikt erop):

- je Mac krijgt een **extra** IP-adres in het subnet van de camera, op de netwerkpoort waarop de camera
  antwoordde (bijvoorbeeld `172.17.100.250/24` naast je eigen `192.168.10.15`);
- je eigen adres blijft gewoon staan, en er verandert niets aan de camera of de rest van de rig;
- het extra adres staat onder *Network* met een knop **Remove**, en wordt automatisch weggehaald als je de
  app afsluit (of de kabel eruit haalt / de Mac herstart).

macOS vraagt om je beheerderswachtwoord, omdat dat nodig is om adressen van een netwerkpoort te wijzigen.
Onder de motorkap is dit `ifconfig <poort> alias <adres> netmask <masker>`.

### De 20-minutenregel

Panasonic-camera's accepteren Easy IP-**wijzigingen** alleen in de eerste **20 minuten nadat ze aan zijn
gezet**. Zoeken werkt altijd. Wil je later nog iets wijzigen: zet de camera uit en weer aan, of zet
*Easy IP Setup accommodate period* op *Unlimited* in de webinterface van de camera (netwerkinstellingen).

De kolom **Easy IP** laat per camera `OPEN` of `LOCKED` zien. Dit is **beta**: de app leest een
ongedocumenteerd statusbit in het antwoord van de camera (byte 57; `0x02` stond aan bij UE150's die al uren
aan stonden, en uit bij één andere camera van dezelfde rig en in opnames waarin wijzigen lukte). Klopt het
een keer niet, open dan een issue.

### Terminal

```bash
EASYIP="/Applications/HBS EasyIP MAC.app/Contents/MacOS/easyip"
"$EASYIP"                                        # camera's weergeven
"$EASYIP" set 00:80:45:6A:1B:2C 10.0.0.21 --mask 255.255.255.0 --gateway 10.0.0.1
```

---

## Hoe Easy IP werkt

| Bericht | Richting | Poort |
|---|---|---|
| Zoeken (`0x0D`) | Mac → `255.255.255.255` | UDP 10670 |
| Aankondiging (`0x0E`) | camera → `255.255.255.255` | UDP 10669 |
| Wijzigen (`0x02`) → bevestiging (`0x03`) → doorvoeren (`0x04`) | op **MAC-adres** binnen de broadcast | 10670 / 10669 |

```
Mac 10.0.0.5 ── broadcast "wie is daar?" ──▶  elke camera op de kabel
                                              (192.168.0.10, 10.20.30.40, …)
Mac         ◀── broadcast "ik ben A8:13:74:…" ──  elke camera, in welk subnet ook
```

Opbouw van een pakket: een header van 48 bytes (versie, lengte, type, MAC van de camera, MAC en IP van de Mac,
stap in de handshake, vast blok), daarna velden als `id / lengte / waarde`, en tot slot `FF FF` en een
16-bit checksum (de som van alle bytes + 1). Velden: `0x20` IP, `0x21` masker, `0x22` gateway, `0x23` 2× DNS,
`0x25` HTTP-poort, `0xA7` titel, `0xA8` `CATEGORIE:MODEL`. Zie
[`Sources/EasyIPKit/Packet.swift`](Sources/EasyIPKit/Packet.swift).

Het formaat is achterhaald uit netwerkopnames van Panasonics eigen tool. De tests controleren dat deze app
**byte voor byte dezelfde** pakketten maakt. Met dank aan
[dPro-Software](https://github.com/dPro-Software/PanasonicEasyIPsetupCore), wiens opnames en notities uit 2018
dit mogelijk maakten.

**Nog niet ingebouwd** (de Windows-tool doet dit via HTTP of met pakketten die nog niemand heeft opgenomen):
Identify (lampje laten knipperen), firmwareversie/serienummer/status, firmware-update, beheerdersaccount
aanmaken, NDI|HX-activatie, DHCP aan/uit, de cameratitel wijzigen.

---

## Ontwikkelen

Nodig: macOS 14+ en Swift 6 (Xcode 16+, of alleen de Command Line Tools).

```bash
swift run EasyIPMac                   # de app starten
swift run easyip                      # het terminalcommando starten
scripts/test.sh                       # tests (werkt ook met alleen de Command Line Tools)
VERSION=0.1.0 scripts/build-app.sh    # → build/HBS EasyIP MAC.app, .dmg, .zip
```

| Map | |
|---|---|
| `Sources/EasyIPKit` | protocol, sockets, netwerkpoorten. Geen interface, geen afhankelijkheden |
| `Sources/EasyIPMac` | de SwiftUI-app; in `HBSTheme.swift` staat de HBS-huisstijl |
| `Sources/easyip` | terminalcommando |
| `Tests/EasyIPKitTests` | tests met echte opgenomen pakketten |
| `tools/fake_camera.py` | **nagebootste camera**, om te testen zonder hardware |

Testen zonder camera's:

```bash
python3 tools/fake_camera.py --mac 02:00:00:00:00:01 --model UE150 &
python3 tools/fake_camera.py --mac 02:00:00:00:00:02 --model HE40 &   # zelfde IP → DUP IP
swift run EasyIPMac
```

### Een nieuwe versie uitbrengen

```bash
git tag v0.2.0 && git push origin v0.2.0
```

GitHub Actions draait de tests, bouwt de app voor Apple Silicon én Intel en zet de `.dmg` en `.zip` als
release online. Wil je een **ondertekende en door Apple gecontroleerde** versie die zonder waarschuwing opent,
voeg dan een Apple Developer ID-certificaat toe als repository secrets (zie
[`.github/workflows/release.yml`](.github/workflows/release.yml)).

### Bijdragen

Het meest gezocht: een Wireshark-opname (`udp.port == 10669 || udp.port == 10670`, plus HTTP) van de
Windows-tool *EasyIPSetupToolPlus* tijdens **Identify**, **Network Settings op een camera met
inlogbeveiliging** en **DHCP aan/uit**. Open een issue en voeg het `.pcapng`-bestand toe.

---

## Licentie

MIT. Niet verbonden aan Panasonic. "Panasonic" en de modelnamen zijn handelsmerken van Panasonic Holdings Corporation.
