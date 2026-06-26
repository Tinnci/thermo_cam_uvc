# Building

ThermoCam UVC is distributed source-first. The recommended path is to build it
locally on the Mac that will run it.

## Requirements

- macOS 15 or newer
- Xcode command line tools or Xcode
- A USB/UVC camera

Check the toolchain:

```sh
xcodebuild -version
swift --version
```

## Build From Source

```sh
git clone <repo-url>
cd thermo_cam_uvc
scripts/build-local.sh
```

The app bundle is written to:

```text
.build/ThermoCamUVC.app
```

Run it with:

```sh
make run
```

The build uses ad-hoc signing with the camera entitlement:

```text
codesign --sign -
```

This is not Developer ID signing and it is not notarization.
