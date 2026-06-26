# Camera Permissions

ThermoCam UVC uses AVFoundation for normal UVC capture. macOS controls camera
access through privacy permissions.

The app declares:

```text
NSCameraUsageDescription
com.apple.security.device.camera
```

On first launch, macOS should ask for camera access. If access is denied:

1. Open System Settings.
2. Go to Privacy & Security.
3. Open Camera.
4. Enable ThermoCam UVC.
5. Restart the app if needed.

The app does not request microphone access and does not directly claim USB
interfaces in the current version. Private Hikvision USB controls are a future
module, separate from the AVFoundation capture path.
