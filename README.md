# Dome Scanner

**Find Panasonic PTZ cameras on any subnet and change their IP address, from a Mac.**
A macOS alternative to Panasonic's Windows-only *Easy IP Setup Tool (Plus)*, for broadcast jobs where you
plug into a rig and need to know where the domes are.

<img src="docs/icon.png" width="128" alt="Dome Scanner icon">

- Tested with AW-UE150, AW-HE130 and the AW-RP120 controller. Should work with every model the Easy IP tool supports
- **Works across subnets.** Your Mac can be on `10.0.0.x` while the cameras are on `192.168.0.10`
- Searches on every network port at once (Wi-Fi, USB/Thunderbolt Ethernet, …)
- Marks cameras that are **in another subnet** ⚠️ or have a **duplicate IP** ⛔
- Change IP / subnet mask / gateway / DNS / port. One click to **move a camera into your Mac's subnet**
- **Auto IP**: give a batch of new cameras (all `192.168.0.10` out of the box) consecutive addresses
- Double-click a camera to open its web interface
- Also included: `domescan`, a command-line version

## Download

Get the latest `.dmg` from [**Releases**](https://github.com/nickfromsad/dome-scanner/releases), open it and drag
*Dome Scanner* to Applications.

> **First launch:** release builds are not notarized by Apple (yet), so macOS blocks the first launch.
> Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or run once in Terminal:
> `xattr -dr com.apple.quarantine "/Applications/Dome Scanner.app"`
>
> When macOS asks, allow **Local Network** access. Without it, no cameras are found.

Command line (inside the app bundle):

```sh
"/Applications/Dome Scanner.app/Contents/MacOS/domescan"                       # list cameras
"/Applications/Dome Scanner.app/Contents/MacOS/domescan" set 00:80:45:6A:1B:2C 10.0.0.21 --mask 255.255.255.0 --gateway 10.0.0.1
```

## The 20-minute rule

Panasonic cameras only accept Easy IP **changes** during the first **20 minutes after power-on**. Searching
always works. To change settings later: power-cycle the camera, or set *Easy IP Setup accommodate period* to
*Unlimited* in the camera's web interface (Network settings).

## How it works

Easy IP is a small proprietary UDP protocol. Everything is **broadcast** to `255.255.255.255`, which is why
the subnet doesn't matter: there is no routing and no ARP, so every device on the same cable/switch/VLAN
receives it.

| Message | Direction | Port |
|---|---|---|
| Search (`0x0D`) | Mac → broadcast | UDP 10670 |
| Announcement (`0x0E`) | camera → broadcast | UDP 10669 |
| Reconfigure (`0x02`) → Ack (`0x03`) → Commit (`0x04`) | addressed by **MAC** inside the broadcast | 10670 / 10669 |

Packet layout: 48-byte header (version, payload length, type, camera MAC, host MAC, host IP, handshake step,
constant block), payload of `id/length/value` fields, then `FF FF` and a 16-bit checksum (sum of all bytes + 1).
Field ids: `0x20` IP, `0x21` mask, `0x22` gateway, `0x23` DNS×2, `0x25` HTTP port, `0xA7` title,
`0xA8` `CATEGORY:MODEL`. See [`Sources/EasyIPKit/Packet.swift`](Sources/EasyIPKit/Packet.swift).

The format was reconstructed from packet captures of Panasonic's tool. The unit tests check that Dome Scanner
produces **byte-identical** packets. Credit to [dPro-Software](https://github.com/dPro-Software/PanasonicEasyIPsetupCore),
whose 2018 captures and notes made this possible.

**Not implemented yet** (the Plus tool does these over HTTP or with packets nobody has captured yet):
Identify (blink LED), firmware version/serial/status, firmware update, administrator registration,
NDI|HX activation, DHCP on/off, setting the camera title. Captures of the Windows tool doing these are very
welcome. See *Contributing*.

## Development

Requires macOS 14+ and Swift 6 (Xcode 16+, or just the Command Line Tools).

```sh
swift run DomeScanner          # run the app
swift run domescan             # run the CLI
scripts/test.sh                # unit tests (works with Command Line Tools only, too)
VERSION=0.1.0 scripts/build-app.sh   # → build/Dome Scanner.app, .dmg, .zip
```

| Path | |
|---|---|
| `Sources/EasyIPKit` | protocol, sockets, interface discovery. No UI, no dependencies |
| `Sources/DomeScanner` | SwiftUI app |
| `Sources/domescan` | command-line tool |
| `Tests/EasyIPKitTests` | tests against real captured packets |
| `tools/fake_camera.py` | **simulated camera** for testing without hardware |
| `tools/easyip_scan.py` | zero-dependency Python scanner (works with the macOS built-in Python) |

Test without cameras:

```sh
python3 tools/fake_camera.py --mac 02:00:00:00:00:01 --model UE150 &
python3 tools/fake_camera.py --mac 02:00:00:00:00:02 --model HE40 &   # same IP → shows as duplicate
swift run DomeScanner
```

### Releasing

```sh
git tag v0.2.0 && git push origin v0.2.0
```

GitHub Actions runs the tests, builds a universal (Apple Silicon + Intel) app and publishes the `.dmg`/`.zip`
as a GitHub Release. To ship a **signed and notarized** build that opens without warnings, add an Apple Developer
ID certificate as repository secrets (see [`.github/workflows/release.yml`](.github/workflows/release.yml)).
A Homebrew cask template lives in [`packaging/homebrew`](packaging/homebrew/dome-scanner.rb).

### Contributing

Most wanted: a Wireshark capture (`udp.port == 10669 || udp.port == 10670`, plus HTTP) of the Windows
*EasyIPSetupToolPlus* doing **Identify**, **Network Settings on a camera with authentication**, and
**DHCP on/off**. Open an issue with the `.pcapng` attached.

## License

MIT. Not affiliated with Panasonic. "Panasonic" and model names are trademarks of Panasonic Holdings Corporation.
