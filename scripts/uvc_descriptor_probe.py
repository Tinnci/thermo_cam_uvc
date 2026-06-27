#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes.util
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import usb.core
import usb.util
from usb.backend import libusb1


CS_INTERFACE = 0x24
CS_ENDPOINT = 0x25

VC_DESCRIPTOR_NAMES = {
    0x01: "VC_HEADER",
    0x02: "VC_INPUT_TERMINAL",
    0x03: "VC_OUTPUT_TERMINAL",
    0x04: "VC_SELECTOR_UNIT",
    0x05: "VC_PROCESSING_UNIT",
    0x06: "VC_EXTENSION_UNIT",
}

VS_DESCRIPTOR_NAMES = {
    0x01: "VS_INPUT_HEADER",
    0x02: "VS_OUTPUT_HEADER",
    0x03: "VS_STILL_IMAGE_FRAME",
    0x04: "VS_FORMAT_UNCOMPRESSED",
    0x05: "VS_FRAME_UNCOMPRESSED",
    0x06: "VS_FORMAT_MJPEG",
    0x07: "VS_FRAME_MJPEG",
    0x10: "VS_FORMAT_FRAME_BASED",
    0x11: "VS_FRAME_FRAME_BASED",
    0x12: "VS_FORMAT_STREAM_BASED",
    0x13: "VS_COLORFORMAT",
}

GUID_FORMATS = {
    "5955593200001000800000aa00389b71": "YUY2",
    "3259555900001000800000aa00389b71": "YUY2",
    "5956595500001000800000aa00389b71": "UYVY",
    "4e56313200001000800000aa00389b71": "NV12",
    "4934323000001000800000aa00389b71": "I420",
    "4d4a504700001000800000aa00389b71": "MJPG",
    "4832363400001000800000aa00389b71": "H264",
}


@dataclass
class ParsedFormat:
    kind: str
    index: int
    name: str


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
    return struct.unpack_from("<H", data, offset)[0]


def le32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def endpoint_type(attributes: int) -> str:
    transfer_type = attributes & 0x03
    return {
        0: "control",
        1: "isochronous",
        2: "bulk",
        3: "interrupt",
    }.get(transfer_type, f"unknown({transfer_type})")


def hs_iso_payload(w_max_packet_size: int) -> int:
    bytes_per_transaction = w_max_packet_size & 0x07FF
    transactions = ((w_max_packet_size >> 11) & 0x03) + 1
    return bytes_per_transaction * transactions


def iter_extra_descriptors(extra: bytes) -> Iterable[bytes]:
    offset = 0
    while offset + 2 <= len(extra):
        length = extra[offset]
        if length < 2 or offset + length > len(extra):
            yield extra[offset:]
            return
        yield extra[offset : offset + length]
        offset += length


def fourcc_from_guid(guid: bytes) -> str:
    hex_guid = guid.hex()
    if hex_guid in GUID_FORMATS:
        return GUID_FORMATS[hex_guid]
    ascii_prefix = guid[:4].decode("ascii", errors="replace")
    if all(32 <= b <= 126 for b in guid[:4]):
        return f"{ascii_prefix} ({hex_guid})"
    return hex_guid


def frame_intervals(data: bytes, offset: int) -> list[float]:
    if len(data) <= offset:
        return []
    count = data[offset]
    values: list[int] = []
    if count == 0 and len(data) >= offset + 13:
        minimum = le32(data, offset + 1)
        maximum = le32(data, offset + 5)
        step = le32(data, offset + 9)
        values = [minimum, maximum, step]
    else:
        for index in range(count):
            item_offset = offset + 1 + index * 4
            if item_offset + 4 <= len(data):
                values.append(le32(data, item_offset))
    return [10_000_000 / value for value in values if value > 0]


def parse_video_control_descriptor(data: bytes) -> str:
    subtype = data[2] if len(data) > 2 else -1
    name = VC_DESCRIPTOR_NAMES.get(subtype, f"VC_SUBTYPE_{subtype}")
    if subtype == 0x01 and len(data) >= 12:
        return (
            f"{name}: UVC {le16(data, 3) >> 8}.{le16(data, 3) & 0xff:02x}, "
            f"totalLength={le16(data, 5)}, clock={le32(data, 7)}Hz"
        )
    if subtype == 0x02 and len(data) >= 8:
        return f"{name}: id={data[3]}, terminalType=0x{le16(data, 4):04x}"
    if subtype == 0x05 and len(data) >= 8:
        return f"{name}: unit={data[3]}, source={data[4]}, maxMultiplier={le16(data, 5)}"
    if subtype == 0x06 and len(data) >= 22:
        guid = data[4:20].hex()
        return f"{name}: unit={data[3]}, guid={guid}, controls={data[21] if len(data) > 21 else 'unknown'}"
    return f"{name}: raw={data.hex()}"


def parse_video_streaming_descriptor(
    data: bytes,
    formats: dict[int, ParsedFormat],
    current_format: ParsedFormat | None,
) -> tuple[str, ParsedFormat | None]:
    subtype = data[2] if len(data) > 2 else -1
    name = VS_DESCRIPTOR_NAMES.get(subtype, f"VS_SUBTYPE_{subtype}")

    if subtype == 0x01 and len(data) >= 14:
        return (
            f"{name}: formats={data[3]}, totalLength={le16(data, 4)}, "
            f"endpoint=0x{data[6]:02x}, stillCaptureMethod={data[9]}, triggerSupport={data[10]}"
        ), current_format

    if subtype == 0x04 and len(data) >= 27:
        index = data[3]
        format_name = fourcc_from_guid(data[5:21])
        formats[index] = ParsedFormat("uncompressed", index, format_name)
        return (
            f"{name}: formatIndex={index}, frames={data[4]}, guid={format_name}, "
            f"bitsPerPixel={data[21]}, defaultFrame={data[22]}"
        ), formats[index]

    if subtype == 0x05 and len(data) >= 26:
        format_name = current_format.name if current_format else "unknown"
        width = le16(data, 5)
        height = le16(data, 7)
        min_bitrate = le32(data, 9)
        max_bitrate = le32(data, 13)
        max_frame = le32(data, 17)
        default_interval = le32(data, 21)
        intervals = frame_intervals(data, 25)
        fps = ", ".join(f"{value:.2f}" for value in intervals)
        return (
            f"{name}: format={current_format.index if current_format else 'unknown'} {format_name}, frameIndex={data[3]}, "
            f"{width}x{height}, defaultFPS={10_000_000 / default_interval:.2f}, "
            f"fps=[{fps}], maxFrame={max_frame}, bitrate={min_bitrate}-{max_bitrate}"
        ), current_format

    if subtype == 0x06 and len(data) >= 11:
        index = data[3]
        formats[index] = ParsedFormat("mjpeg", index, "MJPG")
        return (
            f"{name}: formatIndex={index}, frames={data[4]}, defaultFrame={data[5]}, flags=0x{data[6]:02x}"
        ), formats[index]

    if subtype == 0x07 and len(data) >= 26:
        format_name = current_format.name if current_format else "MJPG"
        width = le16(data, 5)
        height = le16(data, 7)
        max_frame = le32(data, 17)
        default_interval = le32(data, 21)
        intervals = frame_intervals(data, 25)
        fps = ", ".join(f"{value:.2f}" for value in intervals)
        return (
            f"{name}: format={current_format.index if current_format else 'unknown'} {format_name}, frameIndex={data[3]}, "
            f"{width}x{height}, defaultFPS={10_000_000 / default_interval:.2f}, "
            f"fps=[{fps}], maxFrame={max_frame}"
        ), current_format

    if subtype == 0x10 and len(data) >= 28:
        index = data[3]
        format_name = fourcc_from_guid(data[5:21])
        formats[index] = ParsedFormat("frame-based", index, format_name)
        return (
            f"{name}: formatIndex={index}, frames={data[4]}, guid={format_name}, "
            f"bitsPerPixel={data[21]}, defaultFrame={data[22]}, variableSize={data[27]}"
        ), formats[index]

    if subtype == 0x11 and len(data) >= 30:
        format_name = current_format.name if current_format else "unknown"
        width = le16(data, 5)
        height = le16(data, 7)
        max_frame = le32(data, 17)
        default_interval = le32(data, 21)
        intervals = frame_intervals(data, 25)
        fps = ", ".join(f"{value:.2f}" for value in intervals)
        return (
            f"{name}: format={current_format.index if current_format else 'unknown'} {format_name}, frameIndex={data[3]}, "
            f"{width}x{height}, defaultFPS={10_000_000 / default_interval:.2f}, "
            f"fps=[{fps}], maxFrame={max_frame}"
        ), current_format

    return f"{name}: raw={data.hex()}", current_format


def dump_device(vid: int, pid: int) -> int:
    backend = libusb_backend()
    if backend is None:
        print("ERROR: libusb backend not found")
        return 2

    device = usb.core.find(idVendor=vid, idProduct=pid, backend=backend)
    if device is None:
        print(f"ERROR: USB device {vid:04x}:{pid:04x} not found")
        return 1

    print(f"Device {device.idVendor:04x}:{device.idProduct:04x}")
    print(
        "Device descriptor: "
        f"class=0x{device.bDeviceClass:02x}, subclass=0x{device.bDeviceSubClass:02x}, "
        f"protocol=0x{device.bDeviceProtocol:02x}, usb={device.bcdUSB:#06x}, "
        f"configs={device.bNumConfigurations}, maxPacket0={device.bMaxPacketSize0}"
    )
    for index, label in [
        (device.iManufacturer, "manufacturer"),
        (device.iProduct, "product"),
        (device.iSerialNumber, "serial"),
    ]:
        if index:
            try:
                print(f"String {label}: {usb.util.get_string(device, index)}")
            except usb.core.USBError as error:
                print(f"String {label}: <unreadable: {error}>")

    for config in device:
        print(
            f"\nConfiguration {config.bConfigurationValue}: "
            f"attributes=0x{config.bmAttributes:02x}, maxPower={config.bMaxPower * 2}mA"
        )
        formats_by_interface: dict[int, dict[int, ParsedFormat]] = {}
        current_formats_by_interface: dict[int, ParsedFormat | None] = {}
        for interface in config:
            interface_number = interface.bInterfaceNumber
            alternate = interface.bAlternateSetting
            formats = formats_by_interface.setdefault(interface_number, {})
            current_format = current_formats_by_interface.get(interface_number)
            print(
                f"\n  Interface {interface_number} alt {alternate}: "
                f"class=0x{interface.bInterfaceClass:02x}, "
                f"subclass=0x{interface.bInterfaceSubClass:02x}, "
                f"protocol=0x{interface.bInterfaceProtocol:02x}, "
                f"endpoints={interface.bNumEndpoints}"
            )

            extra = bytes(getattr(interface, "extra_descriptors", b"") or b"")
            for descriptor in iter_extra_descriptors(extra):
                if len(descriptor) < 3:
                    print(f"    malformed extra: {descriptor.hex()}")
                    continue
                if descriptor[1] == CS_INTERFACE:
                    if interface.bInterfaceSubClass == 1:
                        print(f"    {parse_video_control_descriptor(descriptor)}")
                    elif interface.bInterfaceSubClass == 2:
                        parsed, current_format = parse_video_streaming_descriptor(
                            descriptor,
                            formats,
                            current_format,
                        )
                        current_formats_by_interface[interface_number] = current_format
                        print(f"    {parsed}")
                    else:
                        print(f"    CS_INTERFACE subtype=0x{descriptor[2]:02x}: {descriptor.hex()}")
                elif descriptor[1] == CS_ENDPOINT:
                    print(f"    CS_ENDPOINT subtype=0x{descriptor[2]:02x}: {descriptor.hex()}")
                else:
                    print(f"    extra dtype=0x{descriptor[1]:02x}: {descriptor.hex()}")

            for endpoint in interface:
                max_packet = endpoint.wMaxPacketSize
                print(
                    f"    Endpoint 0x{endpoint.bEndpointAddress:02x}: "
                    f"{endpoint_type(endpoint.bmAttributes)}, "
                    f"wMaxPacketSize=0x{max_packet:04x} ({hs_iso_payload(max_packet)} bytes/microframe), "
                    f"interval={endpoint.bInterval}"
                )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only UVC descriptor probe for ThermoCamUVC diagnostics.")
    parser.add_argument("--vid", default="0x2bdf", help="USB vendor ID")
    parser.add_argument("--pid", default="0x0101", help="USB product ID")
    args = parser.parse_args()
    return dump_device(int(args.vid, 0), int(args.pid, 0))


if __name__ == "__main__":
    raise SystemExit(main())
