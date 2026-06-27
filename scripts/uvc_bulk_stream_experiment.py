#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes.util
import time
from array import array
from pathlib import Path

import usb.core
import usb.util
from usb.backend import libusb1


VID = 0x2BDF
PID = 0x0101
VS_INTERFACE = 1
VC_INTERFACE = 0
BULK_ENDPOINT = 0x81
PROBE_CONTROL = 0x01
COMMIT_CONTROL = 0x02
SET_CUR = 0x01
GET_CUR = 0x81

ALLOWED_MODES = {
    "yuy2-120x160-25": (1, 1, 120, 160, 25, 38_400),
    "yuy2-240x320-30": (1, 2, 240, 320, 30, 153_600),
    "yuy2-640x360-30": (1, 3, 640, 360, 30, 460_800),
    "mjpg-120x160-25": (2, 1, 120, 160, 25, 38_400),
    "mjpg-240x320-30": (2, 2, 240, 320, 30, 153_600),
    "mjpg-640x360-30": (2, 3, 640, 360, 30, 460_800),
}


def libusb_backend():
    candidates = [
        ctypes.util.find_library("usb-1.0"),
        "/usr/local/lib/libusb-1.0.dylib",
        "/opt/homebrew/lib/libusb-1.0.dylib",
        "/usr/local/opt/libusb/lib/libusb-1.0.dylib",
        "/opt/homebrew/opt/libusb/lib/libusb-1.0.dylib",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return libusb1.get_backend(find_library=lambda _: candidate)
    return libusb1.get_backend()


def le32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "little")


def ctrl_in(device, request: int, selector: int, interface: int, length: int) -> bytes:
    result = device.ctrl_transfer(
        bmRequestType=0xA1,
        bRequest=request,
        wValue=selector << 8,
        wIndex=interface,
        data_or_wLength=length,
        timeout=1000,
    )
    if isinstance(result, array):
        return result.tobytes()
    return bytes(result)


def ctrl_out(device, request: int, selector: int, interface: int, payload: bytes) -> None:
    device.ctrl_transfer(
        bmRequestType=0x21,
        bRequest=request,
        wValue=selector << 8,
        wIndex=interface,
        data_or_wLength=payload,
        timeout=1000,
    )


def make_probe(format_index: int, frame_index: int, fps: int, max_frame: int) -> bytes:
    interval = round(10_000_000 / fps)
    payload = bytearray(26)
    payload[0:2] = (1).to_bytes(2, "little")
    payload[2] = format_index
    payload[3] = frame_index
    payload[4:8] = interval.to_bytes(4, "little")
    payload[18:22] = max_frame.to_bytes(4, "little")
    payload[22:26] = (16 * 1024).to_bytes(4, "little")
    return bytes(payload)


def describe_probe(data: bytes) -> str:
    if len(data) < 26:
        return f"short {len(data)} bytes: {data.hex()}"
    interval = le32(data, 4)
    fps = 10_000_000 / interval if interval else 0
    return (
        f"format={data[2]}, frame={data[3]}, interval={interval} ({fps:.2f} fps), "
        f"maxFrame={le32(data, 18)}, maxPayload={le32(data, 22)}, raw={data.hex()}"
    )


def read_one_frame(device, transfer_size: int, timeout_s: float) -> bytes:
    deadline = time.monotonic() + timeout_s
    chunks: list[bytes] = []
    last_fid: int | None = None

    while time.monotonic() < deadline:
        try:
            result = device.read(BULK_ENDPOINT, transfer_size, timeout=1000)
        except usb.core.USBTimeoutError:
            continue

        packet = result.tobytes() if isinstance(result, array) else bytes(result)
        if len(packet) < 2:
            continue

        header_len = packet[0]
        flags = packet[1]
        fid = flags & 0x01
        eof = bool(flags & 0x02)
        error = bool(flags & 0x40)

        if last_fid is None:
            last_fid = fid
        elif fid != last_fid and chunks:
            return b"".join(chunks)

        if error:
            print(f"payload header reported error: flags=0x{flags:02x}")

        if header_len < len(packet):
            chunks.append(packet[header_len:])

        if eof and chunks:
            return b"".join(chunks)

    return b"".join(chunks)


def run(args: argparse.Namespace) -> int:
    if not args.advanced_uvc_stream:
        print("Refusing to perform USB SET_CUR/claim_interface without --advanced-uvc-stream.")
        print("This script is allowlisted to standard UVC probe/commit for 2bdf:0101 only.")
        return 2

    if args.mode not in ALLOWED_MODES:
        print(f"Mode must be one of: {', '.join(sorted(ALLOWED_MODES))}")
        return 2

    backend = libusb_backend()
    if backend is None:
        print("ERROR: libusb backend not found")
        return 2

    device = usb.core.find(idVendor=VID, idProduct=PID, backend=backend)
    if device is None:
        print("ERROR: HikCamera 2bdf:0101 not found")
        return 1

    config = device.get_active_configuration()
    print(f"Active configuration: {config.bConfigurationValue}")
    detached_interfaces: list[int] = []
    claimed_interfaces: list[int] = []
    interfaces = [VS_INTERFACE]
    if args.claim_control_interface:
        interfaces = [VC_INTERFACE, VS_INTERFACE]

    if args.detach_kernel_driver:
        for interface in interfaces:
            print(f"Attempting to detach kernel driver from interface {interface}.")
            try:
                active = device.is_kernel_driver_active(interface)
                print(f"Kernel driver active on interface {interface}: {active}")
                if active:
                    device.detach_kernel_driver(interface)
                    detached_interfaces.append(interface)
                    print(f"Detached kernel driver from interface {interface}.")
            except (NotImplementedError, usb.core.USBError) as error:
                print(f"DETACH_FAILED interface {interface}: {error}")
                print(
                    "Interpretation: this macOS/libusb path cannot detach Apple's UVC driver "
                    "from user space, even as root."
                )
                return 5

    for interface in interfaces:
        print(f"Attempting to claim interface {interface}.")
        try:
            usb.util.claim_interface(device, interface)
            claimed_interfaces.append(interface)
        except usb.core.USBError as error:
            print(f"CLAIM_FAILED interface {interface}: {error}")
            print(
                "Interpretation: macOS owns the UVC streaming interface. A normal user-space libusb "
                "backend cannot bypass AVFoundation while the Apple camera stack is bound."
            )
            return 3

    try:
        format_index, frame_index, width, height, fps, max_frame = ALLOWED_MODES[args.mode]
        probe = make_probe(format_index, frame_index, fps, max_frame)
        print(f"SET_CUR VS_PROBE {args.mode}: {probe.hex()}")
        ctrl_out(device, SET_CUR, PROBE_CONTROL, VS_INTERFACE, probe)
        negotiated = ctrl_in(device, GET_CUR, PROBE_CONTROL, VS_INTERFACE, 26)
        print(f"GET_CUR VS_PROBE negotiated: {describe_probe(negotiated)}")

        print("SET_CUR VS_COMMIT negotiated probe")
        ctrl_out(device, SET_CUR, COMMIT_CONTROL, VS_INTERFACE, negotiated)

        transfer_size = max(512, min(64 * 1024, le32(negotiated, 22) if len(negotiated) >= 26 else 16 * 1024))
        print(f"Reading bulk endpoint 0x{BULK_ENDPOINT:02x}, transferSize={transfer_size}")
        frame = read_one_frame(device, transfer_size, args.timeout)
        print(f"Read {len(frame)} bytes for first frame candidate ({width}x{height}, expected max {max_frame})")

        if frame:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(frame)
            print(f"Wrote raw frame candidate to {args.output}")
        return 0 if frame else 4
    finally:
        for interface in reversed(claimed_interfaces):
            try:
                usb.util.release_interface(device, interface)
            except (NotImplementedError, usb.core.USBError) as error:
                print(f"RELEASE_FAILED interface {interface}: {error}")
        for interface in reversed(detached_interfaces):
            try:
                device.attach_kernel_driver(interface)
                print(f"Reattached kernel driver to interface {interface}.")
            except (NotImplementedError, usb.core.USBError) as error:
                print(f"REATTACH_FAILED interface {interface}: {error}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Experimental standard-UVC bulk stream probe. This sends SET_CUR VS_PROBE/COMMIT "
            "only when --advanced-uvc-stream is present."
        )
    )
    parser.add_argument("--advanced-uvc-stream", action="store_true")
    parser.add_argument("--detach-kernel-driver", action="store_true")
    parser.add_argument("--claim-control-interface", action="store_true")
    parser.add_argument("--mode", default="yuy2-640x360-30", choices=sorted(ALLOWED_MODES))
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--output", type=Path, default=Path(".analysis/uvc_bulk_first_frame.raw"))
    return run(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
