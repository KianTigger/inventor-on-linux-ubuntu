# WebView2 first-time setup workflow

Microsoft Edge WebView2 Runtime is required by Autodesk Licensing and Identity
components. Downloading the WebView2 installer is not the same as installing the
runtime into the Inventor Wine prefix.

The WebView2 installer must be run after:

1. `scripts/rebuild-prefix.sh` has created the Wine prefix; and
2. a real graphical Linux display is available to Wine.

For a headless server, configure the Inventor X/VNC session first and set
`INVENTOR_DISPLAY` / `INVENTOR_XAUTHORITY` in `inventor.env`.

Then run:

```bash
bash scripts/install-webview2.sh
```

The script:

- checks for an existing WebView2 Runtime using Microsoft's documented
  `{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` registry registration;
- creates a writable Autodesk Licensing WebView2 user-data directory;
- runs the Evergreen x64 installer in the real graphical Wine session;
- waits for the runtime registry registration to appear; and
- fails with a timestamped log if installation does not complete.

Recommended post-rebuild order:

```bash
bash scripts/install-wbemprox-patch.sh
bash scripts/setup-user-integration.sh

# Configure/start the real graphical display here.

bash scripts/install-webview2.sh
bash scripts/doctor.sh
bash scripts/launch-inventor.sh
```

`doctor.sh` treats a built Wine prefix without a registered WebView2 Runtime as
a failure. `launch-inventor.sh` also checks WebView2 before starting Autodesk
Licensing; if it is missing, the launcher invokes `install-webview2.sh` rather
than allowing Autodesk to fail later with "Web browser runtime could not be
initialized".

Microsoft's documented 64-bit WebView2 registration locations are:

- `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`
- `HKCU\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`

At least one `pv` value must contain a version greater than `0.0.0.0`.
