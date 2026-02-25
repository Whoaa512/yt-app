# YTApp

A native macOS YouTube client built with Swift and AppKit. No Electron, no web wrapper framework — just a focused WKWebView shell with the native controls YouTube's web player is missing.

## Why

YouTube in a browser tab fights for attention with everything else. YTApp gives YouTube its own window with:

- **Media key support** — play/pause from your keyboard, headphones, or Touch Bar
- **Persistent playback speed** — set your preferred speed once, it sticks per tab
- **Native tab management** — Cmd+T, Cmd+W, Cmd+1-9, Ctrl+Tab — tabs that behave like a browser
- **Queue system** — intercepts YouTube's "Add to queue" and manages it natively with drag-to-reorder, thumbnails, and auto-advance
- **Theater mode memory** — always opens in theater mode if that's your preference
- **Keyboard-first navigation** — Vimium-style link hints, custom macros, and a help modal
- **History** — SQLite-backed, separate from your browser
- **JS console** — debug window for poking at the page

## Screenshot

*Coming soon*

## Build

Requires Xcode and macOS.

```bash
xcodebuild -scheme YTApp -configuration Debug \
  SYMROOT=$(pwd)/build build
```

The built app lands at `build/Debug/YTApp.app`.

## Architecture

Pure Swift + AppKit. No storyboards, no SwiftUI, no third-party dependencies.

- **WKWebView** hosts YouTube's web player
- **JS injection** bridges YouTube's SPA into native controls (playback state, URL changes, queue interception, theater mode)
- **Message handlers** shuttle events between JS and Swift via `WKScriptMessageHandler`

See [AGENTS.md](AGENTS.md) for the full file map and contribution guide.

## License

MIT
