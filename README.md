# ThermoCam UVC

SPDX-License-Identifier: GPL-3.0-or-later

Mac-first UVC thermal camera app using the system camera stack:

```text
UVC camera -> macOS UVC driver -> CoreMediaIO -> AVFoundation
    -> CMSampleBuffer / CVPixelBuffer -> CVMetalTextureCache / Metal
```

The main path intentionally avoids `libusb` and `libuvc`. Private Hikvision USB
controls, vendor extension units, and virtual camera output are separate future
modules.

## Direction

- Native macOS SwiftUI app target, not Catalyst.
- SwiftUI-first UI with AppKit interop for the preview layer.
- No third-party runtime dependencies in the main app target.
- AVFoundation owns UVC discovery, format negotiation, and capture.
- CoreVideo/Metal stays on the real-time frame path.
- Sandbox and entitlements stay minimal: camera only until a private USB module
  is intentionally added.
- Distribution is source-first. Binary releases, if provided, are ad-hoc signed
  convenience builds, not Developer ID signed and not notarized.

## Build

```sh
make build
make run
```

The app bundle is written to `.build/ThermoCamUVC.app` and ad-hoc signed with
the camera entitlement. The first launch should trigger the macOS camera privacy
prompt because `NSCameraUsageDescription` is present in `Info.plist`.

The build uses only Swift and Apple SDK frameworks. There is no package manager
step and no vendored binary SDK in the main target.

More details:

- [Building](docs/BUILDING.md)
- [Installing ad-hoc builds](docs/INSTALL_ADHOC.md)
- [Camera permissions](docs/CAMERA_PERMISSIONS.md)
- [HikCamera UVC bulk diagnostics](docs/HIKCAMERA_UVC_BULK_DIAGNOSTICS.md)

## Package

For a technical-user binary release:

```sh
make package
```

This writes:

```text
dist/ThermoCamUVC-macos-<arch>-adhoc.zip
dist/SHA256SUMS.txt
```

These artifacts are not Developer ID signed and not notarized. macOS Gatekeeper
may block them. The primary install path remains building from source.

## Release Automation

CI runs on `main` and pull requests with SwiftLint, localization verification,
Swift 6 strict concurrency typecheck, bundle verification, and package creation.

Tagged pushes matching `v*` build the same ad-hoc package and publish a GitHub
Release with the zip and `SHA256SUMS.txt`:

```sh
git tag v0.1.0
git push origin v0.1.0
```

## Current Scope

- Discover built-in and external AVFoundation video devices.
- Select device, resolution, and frame rate from `AVCaptureDevice.Format`.
- Configure `AVCaptureSession`, `AVCaptureDeviceInput`, and
  `AVCaptureVideoDataOutput`.
- Use AVFoundation preview and sample-buffer paths for cameras that deliver
  frames. For the known HikCamera bulk-only profile, the app reports a
  compatibility failure instead of cycling pixel formats or pretending a
  preview-layer-only path is working.
- Import delivered `CVPixelBuffer` frames through `CVMetalTextureCache`.
- Display active format, delivered pixel format, measured FPS, dropped frames,
  Metal import state, and capability-gated controls.
- Save the latest delivered frame as PNG without routing realtime frames through
  SwiftUI image state.
- Record camera output to a QuickTime movie with `AVCaptureMovieFileOutput`
  when the current session graph supports it.
- Inspect `CMSampleBuffer` and `CVPixelBuffer` attachments for thermal,
  radiometric, temperature, or Hikvision metadata keys.
- Show ROI controls and measurement state. Temperature values remain unavailable
  until a vendor radiometric matrix is confirmed in the delivered frame stream
  or through a separate private-control transport.
- Probe Hikvision USB topology as a no-side-effect facts layer with IOKit:
  VID/PID, interface number, interface class/subclass/protocol, and endpoint
  count.
- Interpret USB topology separately from policy. A VC/VS-only Hikvision UVC
  device is treated as a private-control exclusive candidate, not a sideband
  device.
- Expose structured private-control decisions in the UI: transport,
  concurrency, maturity, risk, read-only policy, and write policy.
- Provide Mac-standard Settings, toolbar actions, and Capture menu commands.

## Advanced Features

- Hikvision private USB control is split into four layers:
  USB facts, topology interpretation, capability decision, and control policy.
  The app can refresh facts and enter a read-only probe session plan, but it
  does not claim interfaces or send SET requests.
- For the currently observed `0x2BDF:0x0101` HikCamera, the USB topology exposes
  UVC VideoControl and VideoStreaming interfaces and no independent
  vendor-specific sideband interface. The decision is: sideband unavailable,
  exclusive candidate, read-only probing only after stopping preview, writes
  disabled by policy.
- Virtual camera output is not part of the main app target. It requires a
  separate Core Media I/O Camera Extension/System Extension target when the
  processed feed must appear in apps such as Zoom, Teams, FaceTime, or browsers.
- The main app keeps zero third-party runtime dependencies. Do not add
  `libusb`, `libuvc`, or a vendor binary SDK to the AVFoundation capture path.
  Any HikCamera native USB backend must be an explicit exclusive-mode helper or
  system extension, not hidden inside the normal preview path.

## License

ThermoCam UVC is licensed under `GPL-3.0-or-later`. See [LICENSE](LICENSE).
