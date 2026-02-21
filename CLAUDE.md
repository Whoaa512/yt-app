# YTApp

A native macOS YouTube wrapper built with Swift, AppKit, and WKWebView.

## Build

```bash
cd YTApp && xcodebuild -scheme YTApp -configuration Debug SYMROOT=/Users/cjw/code/yt-app/build build
```

The app runs from `/Users/cjw/code/yt-app/build/Debug/YTApp.app`. **Do not** use default `xcodebuild` without `SYMROOT` — it builds to DerivedData and the user launches from `build/Debug/`.

## Architecture

- **No storyboards/xibs** — all UI is programmatic AppKit (NSWindow, NSView, NSStackView, etc.)
- **Xcode project file** (`YTApp/YTApp.xcodeproj/project.pbxproj`) uses hand-written sequential IDs (AA/BB/CC/DD/EE/FF/GG prefixed). When adding files, continue the pattern (e.g. BB000020, AA000018).
- **JS injection** — scripts in `YTApp/YTApp/JS/` are bundled as resources and injected into WKWebView via `WKUserScript`

## Key Files

- `MainWindowController.swift` — main window, layout, tab/address bar/toolbar wiring, WKWebView delegates
- `TabManager.swift` — tab lifecycle, shared WKWebViewConfiguration, suspension logic
- `ToolbarView.swift` — centered playback/nav toolbar with custom hover buttons
- `AddressBarView.swift` — URL bar with back/forward
- `Tab.swift` — tab model (URL, title, webView, suspension state)
- `MediaBridge.js` — polls video state, posts to Swift via messageHandler
- `URLObserver.js` — hooks pushState/replaceState/yt-navigate-finish for SPA URL tracking
- `DurationExtractor.js` — extracts video duration for history

## YouTube SPA Navigation

YouTube is a Single Page App — clicking videos doesn't trigger WKNavigationDelegate. `URLObserver.js` intercepts `history.pushState`, `history.replaceState`, `popstate`, and YouTube's `yt-navigate-finish` event to keep the address bar and history in sync.

## Style Notes

- Prefer clean, minimal, modern UI — no heavy bezels, subtle hover states, smooth animations
- Custom view subclasses over standard AppKit controls when needed for polish
