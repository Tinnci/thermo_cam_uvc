# HikCamera UVC Bulk Diagnostics

This note records the current macOS diagnosis for the HIKVISION HikCamera
device:

```text
VID: 0x2bdf
PID: 0x0101
USB product: HikCamera
Serial: 12345678
UVC version: 1.10
```

## Evidence

The read-only descriptor probe is:

```sh
uv venv .venv
uv pip install --python .venv/bin/python pyusb
.venv/bin/python scripts/uvc_descriptor_probe.py
```

The device exposes one VideoControl interface and one VideoStreaming interface:

```text
Interface 0 alt 0:
    class 0x0e, subclass 0x01, VideoControl
    endpoint 0x83 interrupt

Interface 1 alt 0:
    class 0x0e, subclass 0x02, VideoStreaming
    endpoint 0x81 bulk
```

The VideoStreaming interface has no isochronous alternate settings. It is a
bulk-only UVC stream.

Supported streaming descriptors:

```text
Format 1: YUY2
    frame 1: 120x160 @ 25 fps
    frame 2: 240x320 @ 30 fps
    frame 3: 640x360 @ 30 fps

Format 2: MJPG
    frame 1: 120x160 @ 25 fps
    frame 2: 240x320 @ 30 fps
    frame 3: 640x360 @ 30 fps

Format 3: H264 frame-based
    frame 1: 240x320
```

The macOS AVFoundation path sees the camera but does not produce frames in the
observed tests. A minimal ffmpeg AVFoundation capture command hangs without
writing a frame:

```sh
ffmpeg -f avfoundation \
  -framerate 30 \
  -video_size 640x360 \
  -pixel_format yuyv422 \
  -i "0:none" \
  -frames:v 1 \
  .analysis/ffmpeg_uvc_640x360_yuyv422.png
```

Read-only UVC class-control requests through libusb fail while the Apple camera
stack owns the device:

```text
GET_CUR VS_PROBE: Access denied
GET_CUR VS_COMMIT: Access denied
GET_INFO Extension Unit 10 Control 1: Access denied
```

The gated native streaming experiment also cannot claim the streaming interface
as a normal user:

```text
CLAIM_FAILED: Access denied
```

Running the same experiment with `sudo` confirms that this is not enough for a
normal app, but it is enough to test an exclusive native backend:

```sh
sudo .venv/bin/python scripts/uvc_bulk_stream_experiment.py \
  --advanced-uvc-stream \
  --detach-kernel-driver \
  --mode yuy2-640x360-30
```

With root and kernel-driver detach, libusb can temporarily detach Apple's UVC
driver, claim interface 1, send standard UVC `VS_PROBE` / `VS_COMMIT`, and read
from bulk endpoint `0x81`.

One run produced a complete JPEG frame:

```text
JPEG image data, 240x320
```

This matched the device's current `VS_PROBE` / `VS_COMMIT` state:

```text
format=2, frame=2, interval=333333, maxFrame=4147200, maxPayload=16384
```

Repeated attempts after USB reset negotiated the standard controls but did not
reliably produce frames. That means the native path is possible, but the startup
sequence is not yet complete.

Read-only probing of Hikvision Extension Unit 10 Control 1 after detaching the
VideoControl interface returned no meaningful state:

```text
GET_INFO: 00
GET_LEN: 0000
GET_CUR: all zeroes
```

## Interpretation

Windows can drive this device through its built-in UVC stack, but this only
proves the device has a standard UVC path that Windows accepts. It does not
prove that macOS AVFoundation can drive the same path.

The important macOS-specific finding is:

```text
The camera is bulk-only UVC video streaming.
macOS binds the device to the system camera stack.
AVFoundation can enumerate the device, but observed AVFoundation clients do not
receive frames.
User-space libusb cannot claim the VideoStreaming interface while the Apple
camera stack owns it.
sudo plus kernel-driver detach can enter an exclusive native backend path, but
that is not something a normal sandboxed SwiftUI app can do inline.
```

Therefore, trying more AVFoundation pixel formats or resolutions is unlikely to
fix preview. The failure is below SwiftUI and below CVPixelBuffer conversion.

## Practical Fix Paths

Short term:

- Keep the AVFoundation backend for cameras that deliver frames.
- Detect this HikCamera profile and report it as a bulk-only UVC compatibility
  failure when no frames arrive.
- Keep private USB writes disabled by default.

Medium term:

- Capture the Windows successful UVC probe/commit sequence with USBPcap and
  compare it with the descriptors above.
- If macOS cannot drive the stream through AVFoundation, implement a separate
  experimental backend outside the normal AVFoundation path.

Native macOS backend options:

- A DriverKit or system-extension USB backend that matches this VID/PID and
  owns the VideoStreaming interface instead of Apple's camera stack.
- A vendor SDK backend if HIKVISION provides a macOS-compatible library.
- A privileged helper tool with explicit advanced-mode UX and strict
  VID/PID/command allowlists. The helper must stop or bypass AVFoundation,
  detach Apple's kernel driver for the relevant interfaces, claim the interfaces,
  and run an exclusive native UVC bulk backend.

Not recommended:

- Blindly cycling YUY2, BGRA, NV12, MJPG, or resolution choices in
  AVFoundation. The observed failure persists before the app receives frames.
- Sending private Extension Unit writes without a captured Windows baseline and
  an allowlisted command model.

## Current Native-Backend Unknowns

The native UVC experiment proves interface ownership can be changed with sudo,
but it does not yet prove a stable frame loop. The remaining unknowns are:

- Whether Windows sends any vendor/class request before `VS_PROBE` / `VS_COMMIT`.
- Whether the camera requires a specific current state, drain, reset, or
  endpoint sequence before bulk packets start.
- Why a request for YUY2 640x360 returned a JPEG 240x320 frame in one run.
- Whether the observed JPEG was an active frame from a previously started stream
  or a stale device/driver state.

The next high-value artifact is still a Windows USBPcap trace of Windows Camera
opening the device.
