# HBS // EasyIP MAC

**English** · [Nederlands](README.nl.md)

<img src="docs/icon.png" width="128" alt="HBS EasyIP MAC icon" align="right">

Find Panasonic PTZ cameras on the network and change their IP address, from a Mac. A macOS alternative to
Panasonic's Windows-only *EasyIP Setup Tool Plus*, for broadcast jobs where you plug into a rig and need to know
where the domes are, even when they sit in a different subnet.

Part of the HBS toolset by [Hof Broadcast Services](https://hofbroadcast.nl), alongside the
[HBS – ATEM Auto Switcher](https://github.com/nickfromsad/HBS---Atem-Auto-Switcher).

---

## What it does

Panasonic cameras speak a small UDP broadcast protocol called *Easy IP*. Every camera on the same cable,
switch or VLAN answers a search, **whatever its IP address or subnet**. This app sends that search on every
network port of your Mac at once, lists every camera it hears back from, and can give a camera a new
address, addressed by its MAC, so it works even when the camera is unreachable over normal IP.

---

## Features

- **Finds every camera.** AW-UE150, HE130, UE100, HE40… plus AW-RP remote controllers, in any subnet
- **All network ports at once.** Wi-Fi, USB/Thunderbolt Ethernet, docks
- **State per camera**: `OK` reachable from this Mac · `SUBNET` in another subnet · `DUP IP` duplicate address
- **Network Settings**: change IP, subnet mask, gateway, DNS and HTTP port
- **Join Subnet**: give your Mac an extra IP address in a camera's subnet and reach its web interface,
  **without changing anything on the camera or the rig**
- **Move into my subnet**: one click fills in a free address in the subnet of your Mac
- **Auto IP**: give a batch of new cameras (all `192.168.0.10` out of the box) consecutive addresses
- **Web interface**: double-click a camera to open it in the browser
- **Auto search**: keeps searching every few seconds and reports cameras that power on or drop off
- **Easy IP `OPEN` / `LOCKED`** (beta): shows whether a camera still accepts changes (see the 20-minute rule)
- **Log**: every search, change and error with a timestamp
- **Update notice**: the header shows when a newer version is on GitHub
- **`easyip` command-line tool** included, for scripting or a quick check from Terminal

Tested with AW-UE150, AW-HE130 and the AW-RP120 controller.

---

## Download

Download `HBS-EasyIP-MAC-x.y.z.dmg` from the [latest release](https://github.com/nickfromsad/HBS-EasyIP-MAC/releases/latest),
open it and drag **HBS EasyIP MAC** to Applications. Requires macOS 14 (Sonoma) or newer, Apple Silicon or Intel.

**First launch.** The app is not notarized by Apple (yet), so macOS blocks the first launch. Open **System
Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or run once in Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/HBS EasyIP MAC.app"
```

When macOS asks, **allow Local Network access**. Without it no cameras are found
(the log then shows *No route to host*).

---

## Usage

1. Connect the Mac to the camera network (any IP address will do).
2. Open **HBS EasyIP MAC**. It searches automatically, and **SEARCH CAMERAS** (⌘R) searches again.
3. Select a camera and click **Network Settings…**, or select several and click **Auto IP…**.
4. **Apply** sends the new settings. The camera confirms, and the list refreshes a few seconds later.

### Join Subnet: reach a camera without changing it

A camera in another subnet (tag `SUBNET`) can't be reached from your Mac. Instead of changing the camera's
IP, select it and click **Join Subnet…** (or double-click it):

- your Mac gets an **extra** IP address in the camera's subnet, on the network port the camera answered on
  (for example `172.17.100.250/24` next to your own `192.168.10.15`);
- your own address stays, nothing changes on the camera or the rest of the rig;
- the extra address is listed under *Network* with a **Remove** button, and is removed automatically when
  you quit the app (or unplug the cable / restart the Mac).

macOS asks for your administrator password, because changing a network port's addresses requires it.
Under the hood this is `ifconfig <port> alias <address> netmask <mask>`.

### The 20-minute rule

Panasonic cameras only accept Easy IP **changes** during the first **20 minutes after power-on**. Searching
always works. To change settings later: power-cycle the camera, or set *Easy IP Setup accommodate period* to
*Unlimited* in the camera's web interface (Network settings).

The **Easy IP** column shows `OPEN` or `LOCKED` per camera. This is **beta**: it reads an undocumented
status bit in the camera's answer (byte 57; `0x02` was set on UE150s that had been on for hours, and clear
on one other camera of the same rig and in captures where changes succeeded). If you see it contradict reality,
please open an issue.

### Command line

```bash
EASYIP="/Applications/HBS EasyIP MAC.app/Contents/MacOS/easyip"
"$EASYIP"                                        # list cameras
"$EASYIP" set 00:80:45:6A:1B:2C 10.0.0.21 --mask 255.255.255.0 --gateway 10.0.0.1
```

---

## How Easy IP works

| Message | Direction | Port |
|---|---|---|
| Search (`0x0D`) | Mac → `255.255.255.255` | UDP 10670 |
| Announcement (`0x0E`) | camera → `255.255.255.255` | UDP 10669 |
| Reconfigure (`0x02`) → Ack (`0x03`) → Commit (`0x04`) | addressed by **MAC** inside the broadcast | 10670 / 10669 |

```
Mac 10.0.0.5 ── broadcast "who is there?" ──▶  every camera on the cable
                                                (192.168.0.10, 10.20.30.40, …)
Mac         ◀── broadcast "I am A8:13:74:…" ──  each camera, whatever its subnet
```

Packet layout: 48-byte header (version, payload length, type, camera MAC, host MAC, host IP, handshake step,
constant block), payload of `id / length / value` fields, then `FF FF` and a 16-bit checksum (sum of all bytes + 1).
Fields: `0x20` IP, `0x21` mask, `0x22` gateway, `0x23` DNS×2, `0x25` HTTP port, `0xA7` title,
`0xA8` `CATEGORY:MODEL`. See [`Sources/EasyIPKit/Packet.swift`](Sources/EasyIPKit/Packet.swift).

The format was reconstructed from packet captures of Panasonic's tool; the unit tests check that this app
produces **byte-identical** packets. Credit to [dPro-Software](https://github.com/dPro-Software/PanasonicEasyIPsetupCore),
whose 2018 captures and notes made this possible.

**Not implemented yet** (the Windows tool does these over HTTP or with packets nobody has captured yet):
Identify (blink LED), firmware version/serial/status, firmware update, administrator registration,
NDI|HX activation, DHCP on/off, setting the camera title.

---

## Development

Requires macOS 14+ and Swift 6 (Xcode 16+, or only the Command Line Tools).

```bash
swift run EasyIPMac                   # run the app
swift run easyip                      # run the command-line tool
scripts/test.sh                       # unit tests (also works with Command Line Tools only)
VERSION=0.1.0 scripts/build-app.sh    # → build/HBS EasyIP MAC.app, .dmg, .zip
```

| Path | |
|---|---|
| `Sources/EasyIPKit` | protocol, sockets, interface discovery. No UI, no dependencies |
| `Sources/EasyIPMac` | SwiftUI app; `HBSTheme.swift` holds the HBS house style |
| `Sources/easyip` | command-line tool |
| `Tests/EasyIPKitTests` | tests against real captured packets |
| `tools/fake_camera.py` | **simulated camera**, for testing without hardware |

Test without cameras:

```bash
python3 tools/fake_camera.py --mac 02:00:00:00:00:01 --model UE150 &
python3 tools/fake_camera.py --mac 02:00:00:00:00:02 --model HE40 &   # same IP → shows DUP IP
swift run EasyIPMac
```

### Releasing

```bash
git tag v0.2.0 && git push origin v0.2.0
```

GitHub Actions runs the tests, builds a universal (Apple Silicon + Intel) app and publishes the `.dmg` and `.zip`
as a GitHub Release. To ship a **signed and notarized** build that opens without warnings, add an Apple Developer
ID certificate as repository secrets (see [`.github/workflows/release.yml`](.github/workflows/release.yml)).

### Contributing

Most wanted: a Wireshark capture (`udp.port == 10669 || udp.port == 10670`, plus HTTP) of the Windows
*EasyIPSetupToolPlus* doing **Identify**, **Network Settings on a camera with authentication**, and
**DHCP on/off**. Open an issue with the `.pcapng` attached.

---

## License

MIT. Not affiliated with Panasonic. "Panasonic" and model names are trademarks of Panasonic Holdings Corporation.
