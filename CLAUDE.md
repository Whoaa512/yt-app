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

## Queue System

- `QueueInterceptor.js` intercepts YouTube's `yt-action` events (capture phase) to hijack "Add to queue"
- `QueueManager.swift` is the singleton queue model, persisted to UserDefaults
- `QueueSidebarView.swift` is an NSTableView-based sidebar with drag-to-reorder
- `ThumbnailCache` (in QueueManager.swift) async-loads thumbnails with NSCache
- oEmbed fallback (`youtube.com/oembed`) fetches title/channel when JS extraction fails
- Queue sidebar toggled with Cmd+Shift+Q, auto-shown when a video is queued

## YouTube DOM Scraping Patterns

YouTube's DOM is complex and changes frequently. Key lessons:

- **Context menus lose DOM context**: When user right-clicks → selects "Add to queue", the `yt-action` event fires *after* the popup menu closes. The original renderer element is no longer "active". Solution: track the last right-clicked renderer via `contextmenu` event listener in capture phase.
- **Renderer elements**: Video metadata lives in `ytd-*-renderer` elements. Common selectors: `ytd-rich-item-renderer`, `ytd-compact-video-renderer`, `ytd-video-renderer`, `ytd-rich-grid-media`.
- **Title**: `#video-title`, `yt-formatted-string#video-title`, or `aria-label` on the title link.
- **Channel**: `ytd-channel-name #text` or `#channel-name a`.
- **Duration**: `ytd-thumbnail-overlay-time-status-renderer span`.
- **Metadata line**: `#metadata-line span` or `.inline-metadata-item` for views/date.
- **Always have a fallback**: DOM extraction is brittle. Use YouTube oEmbed API (`/oembed?url=...&format=json`) as a server-side fallback for title and channel.

## Adding New JS Injections

1. Create the `.js` file in `YTApp/YTApp/JS/`
2. Add `PBXFileReference` (BB prefix) and `PBXBuildFile` (AA prefix) to `project.pbxproj`
3. Add file ref to the JS group (EE000003) and to the Resources build phase
4. Inject in `TabManager.swift`'s `sharedConfiguration` lazy var via `WKUserScript`
5. If it posts messages, register the handler in `MainWindowController.windowDidLoad` and handle in `userContentController(_:didReceive:)`

## Adding New Swift Files

1. Create the `.swift` file in `YTApp/YTApp/`
2. Add `PBXFileReference` (BB prefix) and `PBXBuildFile` (AA prefix) to `project.pbxproj`
3. Add file ref to the YTApp group (EE000002) and to the Sources build phase
4. Next available IDs: check the highest BB/AA numbers in pbxproj and increment

## Pbxproj ID Scheme

| Prefix | Purpose                    | Example    |
|--------|----------------------------|------------|
| AA     | PBXBuildFile entries        | AA000022   |
| BB     | PBXFileReference entries    | BB000024   |
| CC     | Product reference           | CC000001   |
| DD     | PBXFrameworksBuildPhase     | DD000001   |
| EE     | PBXGroup entries            | EE000003   |
| FF     | Build phases, project, configs | FF000011 |
| GG     | XCBuildConfiguration        | GG000004   |

## Style Notes

- Prefer clean, minimal, modern UI — no heavy bezels, subtle hover states, smooth animations
- Custom view subclasses over standard AppKit controls when needed for polish
- Dark background (black/near-black) for WebView container to avoid white flash on load
- NSTableView for lists that need reorder; NSStackView for static layouts
