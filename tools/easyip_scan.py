#!/usr/bin/env python3
"""Proof-of-concept Panasonic Easy IP discovery for macOS (read-only, no dependencies).

Broadcasts an Easy IP search request (UDP 10669 -> 255.255.255.255:10670) on every
IPv4 interface. Cameras answer with a broadcast to port 10669, so they are found even
when they sit in a different subnet than the Mac.

Usage:  python3 easyip_scan.py [seconds]
"""
from __future__ import annotations
import socket
import struct
import subprocess
import sys
import time

SEARCH_PORT = 10670   # cameras listen here
REPLY_PORT = 10669    # cameras broadcast their answer here
IP_BOUND_IF = 25      # macOS: pin a socket to one interface (netinet/in.h)

FIELD_NAMES = {
    0x20: "ip", 0x21: "netmask", 0x22: "gateway", 0x23: "dns", 0x25: "http_port",
    0xA7: "title", 0xA8: "model",
}


def checksum(data: bytes) -> bytes:
    return struct.pack(">H", (sum(data) + 1) & 0xFFFF)


def search_request(src_ip: bytes, src_mac: bytes = bytes([2, 0, 0, 0, 0, 0])) -> bytes:
    requested = [0x20, 0x21, 0x22, 0x23, 0x25, 0x28, 0x40, 0x41, 0x42, 0x44,
                 0xA5, 0xA6, 0xA7, 0xA8, 0xAD, 0xB3, 0xB4, 0xB7, 0xB8]
    body = (bytes([0x00, 0x01, 0x00, 0x2A, 0x00, 0x0D]) + bytes(6) + src_mac + src_ip
            + bytes.fromhex("000020111E11231F1E1913000000010000000000000000000000FFF00026")
            + b"".join(struct.pack(">H", f) for f in requested) + b"\xff\xff")
    return body + checksum(body)


def parse_announcement(pkt: bytes) -> dict | None:
    if len(pkt) < 60 or pkt[:4] != b"\x00\x01\x01\x75":
        return None
    info = {"mac": ":".join(f"{b:02x}" for b in pkt[6:12])}
    cur = 58
    while cur + 4 <= len(pkt):
        fid, flen = struct.unpack(">HH", pkt[cur:cur + 4])
        if fid == 0xFFFF:
            break
        val = pkt[cur + 4:cur + 4 + flen]
        key = FIELD_NAMES.get(fid)
        if key in ("ip", "netmask", "gateway"):
            info[key] = socket.inet_ntoa(val)
        elif key == "dns":
            info[key] = [socket.inet_ntoa(val[i:i + 4]) for i in range(0, len(val), 4)]
        elif key == "http_port":
            info[key] = struct.unpack(">H", val)[0]
        elif key:
            info[key] = val.split(b"\0")[0].decode(errors="replace")
        cur += 4 + flen
    return info


def ipv4_interfaces() -> list[tuple[str, str]]:
    """(interface name, ipv4) for every up interface with a broadcast address."""
    out = subprocess.run(["ifconfig"], capture_output=True, text=True).stdout
    result, name = [], None
    for line in out.splitlines():
        if line and not line[0].isspace():
            name = line.split(":")[0]
        elif "inet " in line and "broadcast" in line:
            result.append((name, line.split()[1]))
    return result


def scan(timeout: float = 3.0) -> list[dict]:
    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    rx.bind(("", REPLY_PORT))

    for ifname, ip in ipv4_interfaces():
        tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        tx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        tx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        tx.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        tx.setsockopt(socket.IPPROTO_IP, IP_BOUND_IF, socket.if_nametoindex(ifname))
        tx.bind((ip, REPLY_PORT))
        tx.sendto(search_request(socket.inet_aton(ip)), ("255.255.255.255", SEARCH_PORT))
        tx.close()
        print(f"  searched on {ifname} ({ip})", file=sys.stderr)

    found, deadline = {}, time.time() + timeout
    while True:
        left = deadline - time.time()
        if left <= 0:
            break
        rx.settimeout(left)
        try:
            pkt, _ = rx.recvfrom(4096)
        except socket.timeout:
            break
        cam = parse_announcement(pkt)
        if cam:
            found[cam["mac"]] = cam
    rx.close()
    return list(found.values())


if __name__ == "__main__":
    cams = scan(float(sys.argv[1]) if len(sys.argv) > 1 else 3.0)
    print(f"{'IP':<16}{'Title':<16}{'Model':<16}{'MAC':<19}{'Mask':<16}{'Gateway':<16}Port")
    for c in sorted(cams, key=lambda c: socket.inet_aton(c.get("ip", "0.0.0.0"))):
        print(f"{c.get('ip',''):<16}{c.get('title',''):<16}{c.get('model',''):<16}{c['mac']:<19}"
              f"{c.get('netmask',''):<16}{c.get('gateway',''):<16}{c.get('http_port','')}")
    print(f"\n{len(cams)} camera(s) found")
