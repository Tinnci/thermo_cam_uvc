#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes.util
from array import array
from pathlib import Path

import usb.core
from usb.backend import libusb1


REQ_GET_CUR = 0x81
REQ_GET_MIN = 0x82
REQ_GET_MAX = 0x83
REQ_GET_RES = 0x84
REQ_GET_LEN = 0x85
REQ_GET_INFO = 0x86
REQ_GET_DEF = 0x87

VS_PROBE_CONTROL = 0x01
VS_COMMIT_CONTROL = 0x02

VC_INTERFACE = 0
VS_INTERFACE = 1
HIKVISION_XU_UNIT = 10
HIKVISION_XU_CONTROL = 1


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


def le16(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "little")


def le32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "little")


def ctrl_in(device, request: int, value: int, index: int, length: int) -> bytes:
    result = device.ctrl_transfer(
        bmRequestType=0xA1,
        bRequest=request,
        wValue=value,
        wIndex=index,
        data_or_wLength=length,
        timeout=1000,
    )
    if isinstance(result, array):
        return result.tobytes()
    return bytes(result)


def parse_probe(data: bytes) -> str:
    if len(data) < 26:
        return f"short({len(data)}): {data.hex()}"
    format_index = data[2]
    frame_index = data[3]
    interval = le32(data, 4)
    max_frame = le32(data, 18)
    max_payload = le32(data, 22)
    fps = 10_000_000 / interval if interval else 0
    return (
        f"hint=0x{le16(data, 0):04x}, format={format_index}, frame={frame_index}, "
        f"interval={interval} ({fps:.2f} fps), keyFrame={le16(data, 8)}, pFrame={le16(data, 10)}, "
        f"quality={le16(data, 12)}, delay={le16(data, 16)}, "
        f"maxFrame={max_frame}, maxPayload={max_payload}, raw={data.hex()}"
    )


def request_name(request: int) -> str:
    return {
        REQ_GET_CUR: "GET_CUR",
        REQ_GET_MIN: "GET_MIN",
        REQ_GET_MAX: "GET_MAX",
        REQ_GET_RES: "GET_RES",
        REQ_GET_DEF: "GET_DEF",
    }[request]


def read_probe_controls(device) -> None:
    for selector, label in [(VS_PROBE_CONTROL, "VS_PROBE"), (VS_COMMIT_CONTROL, "VS_COMMIT")]:
        print(f"\n{label}")
        for request in [REQ_GET_CUR, REQ_GET_MIN, REQ_GET_MAX, REQ_GET_RES, REQ_GET_DEF]:
            try:
                data = ctrl_in(
                    device,
                    request=request,
                    value=selector << 8,
                    index=VS_INTERFACE,
                    length=26,
                )
                print(f"  {request_name(request)}: {parse_probe(data)}")
            except usb.core.USBError as error:
                print(f"  {request_name(request)}: USBError {error}")


def read_extension_unit(device) -> None:
    index = (HIKVISION_XU_UNIT << 8) | VC_INTERFACE
    value = HIKVISION_XU_CONTROL << 8
    print(f"\nExtension Unit {HIKVISION_XU_UNIT} control {HIKVISION_XU_CONTROL}")
    for request, length, label in [
        (REQ_GET_INFO, 1, "GET_INFO"),
        (REQ_GET_LEN, 2, "GET_LEN"),
    ]:
        try:
            data = ctrl_in(device, request=request, value=value, index=index, length=length)
            print(f"  {label}: {data.hex()}")
        except usb.core.USBError as error:
            print(f"  {label}: USBError {error}")

    try:
        length_data = ctrl_in(device, request=REQ_GET_LEN, value=value, index=index, length=2)
        length = le16(length_data, 0)
        if 0 < length <= 4096:
            data = ctrl_in(device, request=REQ_GET_CUR, value=value, index=index, length=length)
            print(f"  GET_CUR({length}): {data.hex()}")
    except usb.core.USBError as error:
        print(f"  GET_CUR: USBError {error}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Read-only UVC class-control probe. Sends only USB IN GET_* requests."
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

    print(f"Device {device.idVendor:04x}:{device.idProduct:04x}")
    read_probe_controls(device)
    read_extension_unit(device)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
