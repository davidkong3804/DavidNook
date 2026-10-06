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
- A slim lyrics capsule under the closed notch: while music plays, the current line scrolls in it one line at a time (static and centered if it fits;
  otherwise it scrolls and finishes before the next line). On by default; Settings → Media turns it off and adjusts distance, maximum width, font size and speed.
  It shares the lyrics, offset and Simplified→Traditional result with the expanded panel; with Reduce Motion it does not scroll and fades out at the end instead.
- Clipboard history (text, images, file paths): search, filter, pin, click to paste back, item limit and retention, pause.
- **Video (new, not verified on real hardware)**: in the expanded notch's Now Playing panel, the album cover has a small, low-key button at its top right.
  It opens the macOS system picker so you can pick **one window**; that window's live, scaled-down picture then **replaces the album cover** (for landscape
  video the cover slot widens without squeezing the title, controls or lyrics; Stop brings the cover back). **Click the video to pin it**: it grows into a
  video capsule outside the notch (collapsed state, right under the notch); click again to unpin. "Change window" and "Stop" appear only on hover and are
  separate from pinning, so they never trigger each other. Only the window you pick is captured; no audio, no cursor; nothing is captured while no window is
  picked or the panel is off screen. Settings → Video turns the feature off and sets the "Video size" (it caps how wide the slot can grow when expanded
  and sets the pinned capsule's size). **Pinned capsule (M-C)**: while the notch is collapsed, the video shows live in a rounded capsule right under the notch,
  stacked vertically with the lyrics capsule (lyrics on top, video below; with no lyrics the video moves up, and it makes room smoothly when lyrics appear).
  When the notch expands the video goes back into the cover slot and the outside capsule fades out, so it is never shown twice. Hovering the capsule counts as hovering the notch
  (click to expand; unpin from the cover slot once expanded), and a small pin appears at its top right on hover. The capsule is clamped to the collapsed window's
  available height (about 164 pt tall under a typical notch, about 291 pt wide at 16:9), scaled down proportionally, and hidden if it would be narrower than 96 pt (for example a very narrow portrait video).
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
- **Video picture**: lives only in memory (handed straight to the display layer and recycled with the stream queue). It is **never saved, uploaded, cached,
  screenshotted or written to the clipboard**, adds no network request, and no audio is captured. Logs contain only states and error codes, never picture
  content, window titles or source app names. Once a second the app samples the picture's average brightness (only to tell whether it is all black); the value
  is not kept. macOS shows its own recording/sharing indicator while capturing.
- **No new entitlements**: Video uses the system window picker, not whole-screen recording permission; Hardened Runtime and entitlements are unchanged.
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
- Screen recording (Video): shows the live picture of the one window you pick. It is **expected** to go through the system picker, where you choose one window
  each time, without pre-authorizing the whole screen. It is only used after you press the small "show a window" button on the album cover; if macOS asks for authorization it asks
  then (**this behavior is not verified on real hardware**).
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

- **YouTube and other video in a browser**: the app guesses the song and artist from the video title (brackets, `Official MV`, `Artist - Title`,
  `feat.`, bilingual titles) and the channel name, then queries LRCLIB. A video is accepted only if it is at most 60 s longer or 5 s shorter than the
  LRCLIB track and the title and artist match the LRCLIB record; otherwise it shows "no lyrics" rather than risk the wrong song. Known limits: lyrics are
  timed to the studio audio, so an intro or spoken part in a music video shifts them early (use the ±0.5 s buttons); title parsing is heuristic;
  live/remix/cover versions and videos longer than 15 minutes are mostly not found; label channels are not used as the artist. Only browser sources
  (by bundle id, or title features when the id is unknown) get this treatment; Apple Music and other clean sources are unchanged. Only the extracted
  title and artist are sent (no raw video title, channel, or duration). **Not verified with real YouTube playback**; the bundle ids browsers actually report need real-world testing.
- Instrumental tracks currently show "no lyrics" (LRCLIB lookups cannot tell them apart from "not found").
- Style issues such as 台→臺 are not handled; one-to-many characters (髮/發) rely on an override table and can still be wrong at the edges.
- Auto-paste is experimental (sandboxed app; depends on macOS accepting the synthesized ⌘V).
- The lyrics capsule has only been checked with offscreen renders and unit tests: not with real playback, and not on a display with a physical notch. On such a display it is drawn inside the visible area and uses a little space below the notch (distance adjustable, default 6 pt). Hovering or clicking it behaves like the notch (expands it); swipe gestures are not handled on the capsule.
- Never tested on a physical display with a notch. Behavior with real Apple Music/Spotify/browser playback is based on limited
  testing; Now Playing relies on private Apple behavior that may change.
- **Video is not verified on real hardware.** Only one minimal hardware trial was done (system picker appears under sandbox + ad-hoc + Hardened Runtime; stream
  about 20 fps at 480 wide; non-black picture). Everything else (real usage feel, browser windows and picture-in-picture windows, windows on other Spaces,
  minimize/close detection, whether a rebuild invalidates authorization, CPU/memory measurements) is **unverified**.
- **Content-protected (DRM) sources are not shown** (for example Netflix, Apple TV): that is the system's protection and this app does **not** and should not try
  to bypass it. When the picture stays black (average brightness below 2/255 for about 3 seconds) it shows a "content-protected" notice; try the source's own
  picture-in-picture or an unprotected source (YouTube, local video). This is a heuristic: a genuinely black scene could be misjudged and recovers as soon as the picture brightens.
- **Other Video limits**: you pick the window again after every launch (the selection is not saved); one window at a time; clicks are not forwarded and the source
  cannot be operated; the picture pauses while the window is minimized; the cover slot only widens when the layout has room (at the smallest panel size it
  stays square and the video is scaled down; notices shrink to a title and buttons, with the full text in a tooltip); pinning is cleared automatically when the
  stream ends (stop, source window closed, error) or when the picture stays black (likely protected) and never survives a relaunch.
- **Pinned capsule limits (M-C)**: while pinned, the stream keeps running even when the notch is collapsed (about 20 fps, no audio), so it **keeps using some GPU/CPU; actual usage is not measured**;
  DRM/black sources never show the capsule (detected black unpins it and the capsule fades out; no black block); with several displays each display's collapsed notch shows the same capsule
  (same approach as the lyrics capsule); **not verified on a display with a physical notch**, and the capsule's feel and animation are untested on real hardware.
- Only Traditional Chinese and English UIs.
