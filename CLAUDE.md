# YTApp

Native macOS YouTube wrapper — Swift, AppKit, WKWebView. No storyboards.

## Build

```bash
cd YTApp && xcodebuild -scheme YTApp -configuration Debug SYMROOT=/Users/cjw/code/yt-app/build build
```

**Important**: Always use `SYMROOT=/Users/cjw/code/yt-app/build` — the app is launched from `build/Debug/YTApp.app`, not DerivedData.

## File Map

### Swift
| File | Role |
|------|------|
| `MainWindowController.swift` | Window, layout, all WKWebView delegates, message handler dispatch |
| `TabManager.swift` | Tab lifecycle, shared WKWebViewConfiguration, JS injection, suspension |
| `Tab.swift` | Tab model (URL, title, webView, suspension state) |
| `ToolbarView.swift` | Playback/nav toolbar with hover buttons, speed controls |
| `AddressBarView.swift` | URL bar with back/forward |
| `QueueManager.swift` | Queue model (singleton, UserDefaults persistence) + ThumbnailCache |
| `QueueSidebarView.swift` | NSTableView sidebar with drag-to-reorder, thumbnails |
| `HistoryManager.swift` | SQLite history |
| `HistoryViewController.swift` | History panel UI |
| `MediaKeyHandler.swift` | MPNowPlayingInfoCenter + remote commands |
| `JSConsoleWindowController.swift` | Dev console for JS evaluation |
| `Settings.swift` | UserDefaults wrapper (playback rate, theater mode, etc.) |
| `URLRouter.swift` | Domain allowlist, external URL handling |

### JavaScript (`YTApp/YTApp/JS/`)
| File | Injection | Role |
|------|-----------|------|
| `MediaBridge.js` | documentEnd | Polls video state → `mediaBridge` handler |
| `URLObserver.js` | documentEnd | SPA navigation tracking → `urlChanged` handler |
| `DurationExtractor.js` | evaluated on demand | Extracts video duration for history |
| `QueueInterceptor.js` | documentStart | Hijacks "Add to queue" → `queueBridge` handler |
| `TheaterMode.js` | documentStart | Persists `wide=1` cookie for theater mode |

### Message Handlers (Swift ↔ JS bridge)
| Handler | Direction | Purpose |
|---------|-----------|---------|
| `mediaBridge` | JS→Swift | Video playback state (paused, ended, time, title) |
| `urlChanged` | JS→Swift | SPA URL changes for address bar + history |
| `queueBridge` | JS→Swift | Intercepted queue additions with video metadata |
| `consoleLog` | JS→Swift | Debug logging to JS console window |
| `theaterChanged` | JS→Swift | Theater mode toggle state sync |

## Adding Files

### New JS injection
1. Create `.js` in `YTApp/YTApp/JS/`
2. pbxproj: add `BB______` (PBXFileReference) + `AA______` (PBXBuildFile)
3. pbxproj: add to JS group (`EE000003`) + Resources build phase
4. `TabManager.swift`: inject via `WKUserScript` in `sharedConfiguration`
5. If it posts messages: register handler in `MainWindowController.windowDidLoad`, handle in `userContentController(_:didReceive:)`

### New Swift file
1. Create `.swift` in `YTApp/YTApp/`
2. pbxproj: add `BB______` (PBXFileReference) + `AA______` (PBXBuildFile)
3. pbxproj: add to YTApp group (`EE000002`) + Sources build phase

### Pbxproj IDs
Sequential, prefixed: **AA** (build files), **BB** (file refs), **CC** (products), **DD** (frameworks phase), **EE** (groups), **FF** (build phases/project), **GG** (build configs). Check highest existing number and increment.

## YouTube Gotchas

**SPA navigation**: Clicking videos doesn't trigger WKNavigationDelegate. `URLObserver.js` hooks `pushState`, `replaceState`, `popstate`, and `yt-navigate-finish`.

**DOM scraping is brittle**: YouTube's markup changes. Key patterns:
- Video metadata lives in `ytd-*-renderer` elements (`ytd-rich-item-renderer`, `ytd-compact-video-renderer`, `ytd-video-renderer`, `ytd-rich-grid-media`)
- Title: `#video-title` or `aria-label` on title link
- Channel: `ytd-channel-name #text` or `#channel-name a`
- Duration: `ytd-thumbnail-overlay-time-status-renderer span`
- Views/date: `#metadata-line span` or `.inline-metadata-item`
- **Context menus lose DOM context** — the `yt-action` event fires after the popup closes. Track the renderer via `contextmenu` listener in capture phase.
- **Always have a fallback**: oEmbed API (`/oembed?url=...&format=json`) for title/channel when DOM extraction fails.

## Workflow

- **Commit in logical chunks** as you go — don't wait until the end. Group related changes into a single commit with a descriptive message.

## Style

- Minimal, modern — no heavy bezels, subtle hover states, smooth animations
- Dark backgrounds (black/near-black) for WebView container — no white flash
- NSTableView for reorderable lists; NSStackView for static layouts
- Custom NSView subclasses over standard AppKit controls when needed for polish
