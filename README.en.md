# DavidNook

A macOS notch utility: **fully local — no server, no telemetry, no auto-update, no AI, no account.**

[繁體中文說明](README.md) (the primary README)

DavidNook turns the notch (or a floating notch on displays without one) into a small panel that shows the current track with
synced lyrics and keeps a clipboard history. It is a **GPL-3.0 derivative work** of
[boring.notch](https://github.com/TheBoredTeam/boring.notch) (The Bored Team and contributors; forked from tag `v2.8-rc.1`,
commit `fb2643121741c6ba6102d5ef2b2c7a787f26fad1`, upstream history and file-header credits preserved).
DavidNook is an independent implementation and is **not affiliated with NotchNook or its authors**.

## Features

- Notch expand/collapse on hover, multiple displays, displays without a notch, gestures, compact mode.
- Now Playing with line-by-line synced lyrics from [LRCLIB](https://lrclib.net). Simplified Chinese lyrics are converted to
  Traditional Chinese (OpenCC `s2tw` plus an override table; native Traditional lyrics are left alone; Taiwan idiom
  conversion is off by default).
- Clipboard history (text, images, file paths): search, filter, pin, click to paste back, item limit and retention, pause.
- Playback controls (previous / play-pause / next, shuffle, repeat, seek, volume; favorites for the Music app).
- UI languages: Traditional Chinese when the system language is Traditional Chinese, English otherwise.

## Privacy

- Everything stays on this Mac. The app is sandboxed; lyrics cache and clipboard history live in the container's
  Application Support (`~/Library/Containers/io.github.davidkong3804.DavidNook/Data/Library/Application Support/DavidNook/`),
  files `0600`, directories `0700`. Settings let you clear them.
- **The only network connection is `lrclib.net`** (lyrics lookup). It receives the **track title, artist and duration** and a
  `User-Agent: DavidNook/<version> (project URL)`. It does **not** receive the album, clipboard content, file paths or any
  identifier. (The server sees your IP address, as with any request.) Turn lyrics off in Settings → Media to disable it.
- No telemetry, no update server, no content in logs.
- Clipboard: items marked as passwords or one-time content (`org.nspasteboard.ConcealedType` and friends) are skipped;
  text over 1 MB and images over 20 MB are not recorded.

## Requirements

- macOS 14 or later (built and verified on macOS 27 with Xcode 27). Building needs full Xcode, no developer account.
- The architecture follows the build output: **by default only the host architecture is built**. On Apple Silicon:

  ```sh
  lipo -archs build/DavidNook.app/Contents/MacOS/DavidNook
  # arm64
  ```

  The embedded adapter framework is `x86_64 arm64`, but the app itself is not universal. Building on Intel is untested.

## Build and ad-hoc signing

The app is signed ad hoc (`codesign --sign -`). There is no developer account, so it **cannot be notarized**.

```sh
Tools/build_release.sh                       # Release, ad hoc -> build/DavidNook.app (prints signature + entitlements)
Tools/install.sh                             # copy to ~/Applications (no sudo, no login items)
Tools/install.sh --dest "$HOME/Applications/Test"
open "$HOME/Applications/DavidNook.app"
codesign --verify --deep --strict build/DavidNook.app
cd Packages/DavidNookCore && swift test      # pure-logic package tests
```

- `Tools/build_release.sh --help` lists the options. `cmake` is only needed for `--rebuild-adapter`
  (rebuilds mediaremote-adapter from upstream source via `Tools/build_adapter.sh`).
- A locally built app has no quarantine attribute and normally is not blocked by Gatekeeper. If a copy you got elsewhere is
  blocked, follow the system prompt, or just build it yourself.
- **Every rebuild changes the ad-hoc cdhash**, so permissions you granted before (Automation, Accessibility) may need to be
  granted again.

## First launch and permissions

A welcome window explains what DavidNook does and which permissions it uses. **It only explains; it never triggers a system
permission prompt.**

- Automation for the Music app: fallback when system Now Playing is unavailable, and favorites/volume while the Music app is
  playing. macOS asks the first time it is needed.
- Paste from Other Apps (macOS 15.4+): needed by clipboard history; asked the first time the clipboard is read.
- Accessibility / post events: only for the experimental "paste automatically after choosing" option (off by default), requested
  only when you press the button in Settings → Clipboard.

## Troubleshooting

- **Crash at launch with `mapping process and mapped file (non-platform) have different Team IDs`**: library validation.
  An ad-hoc signature has no Team ID, so Hardened Runtime refuses a framework that is *linked* into the app. The fix is that the
  mediaremote-adapter framework is **embedded only, never linked** (upstream designed it to be loaded by `/usr/bin/perl`).
  **Do not "fix" this by disabling Hardened Runtime.** `Tools/build_release.sh` checks both after building.
  See `Vendor/mediaremote-adapter/PROVENANCE.md`.
- No lyrics: check Settings → Media and that `lrclib.net` is reachable; instrumental tracks and tracks LRCLIB does not have show
  "no lyrics". Use the ±0.5 s buttons on the lyrics panel to adjust timing.
- Clipboard panel asks for paste permission: set DavidNook to Allow under System Settings → Privacy & Security → Paste from Other Apps.

## Uninstall

Turn off "Launch at login" in Settings → General, quit the app, delete `DavidNook.app`, then:

```sh
rm -rf ~/Library/Containers/io.github.davidkong3804.DavidNook
```

## License and credits

GPL-3.0 ([`LICENSE`](LICENSE)), no warranty. Third-party components: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and
[`LICENSES/`](LICENSES/) (also bundled in the app: Settings → About). Thanks to boring.notch, Atoll, ungive/mediaremote-adapter
(BSD-3-Clause), LRCLIB, OpenCC and SwiftyOpenCC, Sindre Sorhus' Defaults / KeyboardShortcuts / LaunchAtLogin-Modern,
MacroVisionKit, SkyLightWindow, DynamicNotchKit and Parrot (MPL-2.0).

## Known limitations

- Instrumental tracks currently show "no lyrics" (LRCLIB lookups cannot tell them apart from "not found").
- Style issues such as 台→臺 are not handled; one-to-many characters (髮/發) rely on an override table and can still be wrong at the edges.
- Auto-paste is experimental (sandboxed app; depends on macOS accepting the synthesized ⌘V).
- Never tested on a physical display with a notch. Behavior with real Apple Music/Spotify/browser playback is based on limited
  testing; Now Playing relies on private Apple behavior that may change.
- Only Traditional Chinese and English UIs.
