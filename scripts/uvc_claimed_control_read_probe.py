#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes.util
from array import array
from pathlib import Path

import usb.core
import usb.util
from usb.backend import libusb1


REQ_GET_CUR = 0x81
REQ_GET_MIN = 0x82
REQ_GET_MAX = 0x83
REQ_GET_RES = 0x84
REQ_GET_LEN = 0x85
REQ_GET_INFO = 0x86
REQ_GET_DEF = 0x87

VC_INTERFACE = 0
VS_INTERFACE = 1
VS_PROBE_CONTROL = 0x01
VS_COMMIT_CONTROL = 0x02


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


def bytes_from_result(result) -> bytes:
    if isinstance(result, array):
        return result.tobytes()
    return bytes(result)


def le16(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "little")


def le32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "little")


def ctrl_in(device, request: int, value: int, index: int, length: int) -> bytes:
    return bytes_from_result(
        device.ctrl_transfer(
            bmRequestType=0xA1,
            bRequest=request,
            wValue=value,
            wIndex=index,
            data_or_wLength=length,
            timeout=1000,
        )
    )


def parse_probe(data: bytes) -> str:
    if len(data) < 26:
        return f"short({len(data)}): {data.hex()}"

    interval = le32(data, 4)
    fps = 10_000_000 / interval if interval else 0
    return (
        f"hint=0x{le16(data, 0):04x}, format={data[2]}, frame={data[3]}, "
        f"interval={interval} ({fps:.2f} fps), maxFrame={le32(data, 18)}, "
        f"maxPayload={le32(data, 22)}, raw={data.hex()}"
    )


def request_name(request: int) -> str:
    return {
        REQ_GET_CUR: "GET_CUR",
        REQ_GET_MIN: "GET_MIN",
        REQ_GET_MAX: "GET_MAX",
        REQ_GET_RES: "GET_RES",
        REQ_GET_DEF: "GET_DEF",
    }[request]


def read_stream_controls(device) -> None:
    for selector, label in [(VS_PROBE_CONTROL, "VS_PROBE"), (VS_COMMIT_CONTROL, "VS_COMMIT")]:
        print(f"\n{label}")
        for request in [REQ_GET_CUR, REQ_GET_MIN, REQ_GET_MAX, REQ_GET_RES, REQ_GET_DEF]:
            try:
                data = ctrl_in(device, request, selector << 8, VS_INTERFACE, 26)
                print(f"  {request_name(request)}: {parse_probe(data)}")
            except usb.core.USBError as error:
                print(f"  {request_name(request)}: USBError {error}")


def scan_extension_units(device) -> None:
    print("\nExtension unit read-only scan")
    for unit in range(1, 16):
        for control in range(1, 8):
            value = control << 8
            index = (unit << 8) | VC_INTERFACE
            try:
                info = ctrl_in(device, REQ_GET_INFO, value, index, 1)
            except usb.core.USBError:
                continue

            try:
                length = ctrl_in(device, REQ_GET_LEN, value, index, 2)
                length_value = le16(length, 0) if len(length) >= 2 else 0
            except usb.core.USBError as error:
                print(f"  unit={unit} control={control} INFO={info.hex()} LEN=USBError {error}")
                continue

            print(f"  unit={unit} control={control} INFO={info.hex()} LEN={length.hex()}")
            if 0 < length_value <= 256:
                try:
                    current = ctrl_in(device, REQ_GET_CUR, value, index, length_value)
                    print(f"    GET_CUR({length_value}): {current.hex()}")
                except usb.core.USBError as error:
                    print(f"    GET_CUR({length_value}): USBError {error}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Detach/claim UVC interfaces, then send only read-only UVC GET_* requests."
    )
    parser.add_argument("--vid", default="0x2bdf")
    parser.add_argument("--pid", default="0x0101")
    args = parser.parse_args()

    backend = libusb_backend()
    if backend is None:
        print("ERROR: libusb backend not found")
        return 2

    device = usb.core.find(idVendor=int(args.vid, 0), idProduct=int(args.pid, 0), backend=backend)
    if device is None:
        print(f"ERROR: USB device {args.vid}:{args.pid} not found")
        return 1

    print(f"Device {device.idVendor:04x}:{device.idProduct:04x}, bcdDevice=0x{device.bcdDevice:04x}")
    detached_interfaces: list[int] = []
    claimed_interfaces: list[int] = []

    try:
        for interface in [VC_INTERFACE, VS_INTERFACE]:
            active = device.is_kernel_driver_active(interface)
            print(f"Kernel driver active on interface {interface}: {active}")
            if active:
                device.detach_kernel_driver(interface)
                detached_interfaces.append(interface)
                print(f"Detached kernel driver from interface {interface}.")

        for interface in [VC_INTERFACE, VS_INTERFACE]:
            usb.util.claim_interface(device, interface)
            claimed_interfaces.append(interface)
            print(f"Claimed interface {interface}.")

        read_stream_controls(device)
        scan_extension_units(device)
        return 0
    finally:
        for interface in reversed(claimed_interfaces):
            try:
                usb.util.release_interface(device, interface)
                print(f"Released interface {interface}.")
            except (NotImplementedError, usb.core.USBError) as error:
                print(f"RELEASE_FAILED interface {interface}: {error}")
        for interface in reversed(detached_interfaces):
            try:
                device.attach_kernel_driver(interface)
                print(f"Reattached kernel driver to interface {interface}.")
            except (NotImplementedError, usb.core.USBError) as error:
                print(f"REATTACH_FAILED interface {interface}: {error}")


if __name__ == "__main__":
    raise SystemExit(main())
