#!/usr/bin/env python3
"""Pretends to be a Panasonic PTZ camera speaking Easy IP, for testing without hardware.

Answers search requests with an announcement and accepts IP changes via the
request -> ack -> commit handshake, like the AW-HE130 in the reference captures.

Usage:  python3 tools/fake_camera.py [--ip 192.168.0.10] [--mac A8:13:74:00:00:01] [--model UE150] [--title CAM-1] [--locked]
Run several with different --mac values to simulate a rig of cameras.
"""
import argparse
import socket
import struct

CAMERA_PORT, HOST_PORT = 10670, 10669
MAGIC = bytes.fromhex("20111E11231F1E1913")


def frame(msg_type, camera_mac, host_mac, host_ip, step, mode, payload):
    head = (b"\x00\x01" + struct.pack(">HH", len(payload), msg_type) + camera_mac + host_mac + host_ip
            + struct.pack(">H", step) + MAGIC + mode)
    body = head + bytes(48 - len(head)) + payload + b"\xff\xff"
    return body + struct.pack(">H", (sum(body) + 1) & 0xFFFF)


def tlv(field, value):
    return struct.pack(">HH", field, len(value)) + value


def text16(s):
    return s.encode()[:16].ljust(16, b"\0")


def parse_fields(pkt):
    fields, cur = {}, 58
    while cur + 4 <= len(pkt) - 4:
        fid, flen = struct.unpack(">HH", pkt[cur:cur + 4])
        fields[fid] = pkt[cur + 4:cur + 4 + flen]
        cur += 4 + flen
    return fields


class FakeCamera:
    def __init__(self, mac, ip, mask, gateway, model, title, locked=False):
        self.mac, self.model, self.title, self.locked = mac, model, title, locked
        self.ip, self.mask, self.gateway = map(socket.inet_aton, (ip, mask, gateway))
        self.dns, self.port = bytes(8), 80
        self.pending = None

    def announcement(self, host_mac, host_ip):
        eui64 = bytes([self.mac[0] ^ 2]) + self.mac[1:3] + b"\xff\xfe" + self.mac[3:]
        port = struct.pack(">H", self.port)
        # Last preamble byte: 0x02 = Easy IP changes locked (20 min after power-on), as seen on real UE150s.
        payload = (bytes.fromhex("000000010200010001") + (b"\x02" if self.locked else b"\x00")
                   + tlv(0x20, self.ip) + tlv(0x21, self.mask) + tlv(0x22, self.gateway)
                   + tlv(0x23, self.dns) + tlv(0x25, port)
                   + tlv(0x40, bytes.fromhex("fe800000000000") + b"\x00" + eui64)
                   + tlv(0x41, bytes(16)) + tlv(0x42, bytes(32)) + tlv(0x44, port)
                   + tlv(0xA0, self.ip) + tlv(0xA1, self.mask) + tlv(0xA2, self.gateway)
                   + tlv(0xA3, self.dns) + tlv(0xA6, b"\x92")
                   + tlv(0xA7, text16(self.title)) + tlv(0xA8, text16("CAM:" + self.model)))
        return frame(0x0E, self.mac, host_mac, host_ip, 0, bytes.fromhex("00000202"), payload)

    def handle(self, pkt):
        """Returns a reply packet or None."""
        if len(pkt) < 52 or pkt[24:33] != MAGIC or pkt[-2:] != struct.pack(">H", (sum(pkt[:-2]) + 1) & 0xFFFF):
            return None
        msg_type = struct.unpack(">H", pkt[4:6])[0]
        host_mac, host_ip = pkt[12:18], pkt[18:22]
        if msg_type == 0x0D:
            print(f"search from {socket.inet_ntoa(host_ip)}")
            return self.announcement(host_mac, host_ip)
        if pkt[6:12] != self.mac:
            return None
        if msg_type == 0x02 and self.locked:
            print("reconfigure request ignored: Easy IP is locked")
            return None
        if msg_type == 0x02:
            self.pending = parse_fields(pkt)
            print(f"reconfigure request: new IP {socket.inet_ntoa(self.pending[0x20])}, sending ack")
            return frame(0x03, self.mac, host_mac, host_ip, 1, bytes.fromhex("00000202"), b"")
        if msg_type == 0x04 and self.pending:
            f, self.pending = self.pending, None
            self.ip, self.mask, self.gateway, self.dns = f[0x20], f[0x21], f[0x22], f[0x23]
            self.port = struct.unpack(">H", f[0x25])[0]
            print(f"commit: now {socket.inet_ntoa(self.ip)}/{socket.inet_ntoa(self.mask)} gw {socket.inet_ntoa(self.gateway)}")
        return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mac", default="A8:13:74:76:A8:6B")
    ap.add_argument("--ip", default="192.168.0.10")
    ap.add_argument("--mask", default="255.255.255.0")
    ap.add_argument("--gateway", default="192.168.0.1")
    ap.add_argument("--model", default="HE130")
    ap.add_argument("--title", help="camera title (default: AW-<model>, like a factory-new camera)")
    ap.add_argument("--locked", action="store_true", help="behave like a camera powered on >20 min ago (ignores changes)")
    a = ap.parse_args()
    cam = FakeCamera(bytes.fromhex(a.mac.replace(":", "").replace("-", "")), a.ip, a.mask, a.gateway, a.model, a.title or "AW-" + a.model, a.locked)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind(("", CAMERA_PORT))
    print(f"fake AW-{a.model} {a.mac} at {a.ip}, listening on UDP {CAMERA_PORT}")
    while True:
        pkt, _ = sock.recvfrom(4096)
        reply = cam.handle(pkt)
        if reply:
            sock.sendto(reply, ("255.255.255.255", HOST_PORT))


if __name__ == "__main__":
    main()
