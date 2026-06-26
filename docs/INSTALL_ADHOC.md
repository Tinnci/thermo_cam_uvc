# Installing Ad-Hoc Builds

Binary releases are optional convenience builds for technical users. They are
ad-hoc signed, not Developer ID signed, and not notarized.

For the safest path, build from source:

```sh
scripts/build-local.sh
```

## What To Expect

If you download a release zip from a browser, macOS may show a Gatekeeper warning
such as:

```text
Apple cannot check this app for malicious software.
```

or:

```text
The developer cannot be verified.
```

This is expected for non-notarized builds. It does not mean the app is trusted by
macOS.

## Open Anyway

If you trust the source and the release artifact, the standard macOS override is:

1. Try to open the app once.
2. Open System Settings.
3. Go to Privacy & Security.
4. Use Open Anyway for ThermoCam UVC.

Avoid treating quarantine removal commands as the normal install path. They are
for advanced users who understand the Gatekeeper tradeoff.

## Verify The Download

If the release provides `SHA256SUMS.txt`, verify the archive before opening it:

```sh
cd path/to/release-files
shasum -a 256 -c SHA256SUMS.txt
```
