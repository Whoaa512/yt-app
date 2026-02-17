# YT App — Native macOS YouTube Client

## Vision
A dedicated, lightweight macOS app for YouTube Premium users. Own Cmd-Tab presence, minimal memory footprint, browser-style tabs with suspension. Built with Swift + WKWebView.

---

## V1 — MVP

### Architecture
- **Language**: Swift (latest, macOS 15+)
- **UI Framework**: AppKit (not SwiftUI — better control over tab bar, WebView lifecycle, window chrome)
- **Web Engine**: WKWebView (Safari/WebKit engine)
- **Storage**: SQLite via `GRDB.swift` or raw SQLite3 C API for history
- **Distribution**: `.dmg` (outside App Store)
- **Build**: Xcode project, or Swift Package Manager + `xcodebuild`

### Features

#### 1. Window & Chrome
- Minimal native window: tab bar + address bar + WebView
- No bookmarks bar, no sidebar (V1)
- Standard macOS window controls (close, minimize, fullscreen)
- Remember window size/position on quit

#### 2. Tab Bar
- Native horizontal tab bar across the top (NSTabView or custom view)
- Unlimited tabs, horizontally scrollable when they overflow
- Cmd+T = new tab (opens youtube.com)
- Cmd+W = close tab
- Cmd+Shift+] / Cmd+Shift+[ = next/prev tab
- Drag to reorder
- Tab shows: favicon + page title (truncated)
- Close button on hover per tab
- Middle-click or Cmd+click on YouTube links = open in new tab

#### 3. Tab Suspension
- Tabs inactive for >5 minutes: deallocate WKWebView, retain only URL + title + scroll position
- Visual indicator on suspended tabs (dimmed or small icon)
- Clicking a suspended tab re-creates the WebView and loads the URL
- YouTube handles session restoration well via its own local storage
- Memory target: suspended tab = ~0 bytes WebView overhead (just a URL string + metadata)

#### 4. Address Bar
- Single input field above the WebView
- If input looks like a URL → navigate directly
- If input is plain text → redirect to `youtube.com/results?search_query=...`
- Shows current URL while browsing
- Cmd+L = focus address bar
- Standard back/forward buttons (or Cmd+[ / Cmd+])

#### 5. Navigation & URL Scope
- Allow navigation to: `*.youtube.com`, `*.google.com`, `accounts.google.com`, `*.gstatic.com`, `*.googleapis.com`
- Google domains needed for SSO login flow
- Any other domain: block or open in default browser
- Back / Forward buttons wired to WKWebView's `goBack()` / `goForward()`

#### 6. Google SSO / Authentication
- WKWebView with a persistent `WKWebsiteDataStore` (non-ephemeral)
- This preserves cookies across launches — stay logged in
- Enable JavaScript, allow cookies (including third-party for Google auth flow)
- WKWebView config:
  ```
  let config = WKWebViewConfiguration()
  config.websiteDataStore = WKWebsiteDataStore.default() // persistent
  ```
- All tabs share the same data store = single login session

#### 7. History
- SQLite database at `~/Library/Application Support/YTApp/history.db`
- Schema:
  ```sql
  CREATE TABLE history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    url TEXT NOT NULL,
    title TEXT,
    duration TEXT,        -- video duration string e.g. "12:34"
    visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
  CREATE INDEX idx_history_visited_at ON history(visited_at DESC);
  CREATE INDEX idx_history_title ON history(title);
  ```
- Record a history entry on every `youtube.com/watch?v=` page load
- Extract video title from page title (WKWebView `title` property, strip " - YouTube" suffix)
- Extract duration: inject small JS snippet to read from the video player DOM or page metadata
- History view: Cmd+Y opens a sheet/panel with:
  - Search field (filters by title, URL)
  - Scrollable list: title, duration, URL, timestamp
  - Click to open in current tab
  - Delete button per row
  - "Clear All History" button with confirmation
- Deduplicate: if same URL visited within 1 minute, update timestamp instead of inserting

#### 8. Media Keys & Now Playing
- Integrate with `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`
- Play/pause, next track, previous track commands
- Communicate with YouTube's player via injected JavaScript:
  - `document.querySelector('video').play()`
  - `document.querySelector('video').pause()`
  - `document.querySelector('.ytp-next-button').click()`
- Update Now Playing info:
  - Title: from page title
  - Artist: channel name (extract via JS from DOM)
  - Duration / elapsed: from `<video>` element properties
- Poll or observe playback state every ~1s to keep Now Playing widget in sync

#### 9. Settings (Minimal)
- Link click behavior: "Open in same tab" vs "Open in new tab" (default: same tab, Cmd+click = new tab)
- Tab suspension timeout: 5 min (default), configurable
- Stored in `UserDefaults`

### File Structure
```
YTApp/
├── YTApp.xcodeproj
├── YTApp/
│   ├── AppDelegate.swift          # App lifecycle
│   ├── MainWindowController.swift # Window + tab bar + address bar
│   ├── TabManager.swift           # Tab state, suspension, creation/deletion
│   ├── Tab.swift                  # Model: url, title, duration, webView?, suspended
│   ├── WebViewController.swift    # WKWebView setup, navigation delegate, JS injection
│   ├── AddressBarView.swift       # Search/URL input field
│   ├── HistoryManager.swift       # SQLite operations
│   ├── HistoryViewController.swift# History panel UI
│   ├── MediaKeyHandler.swift      # MPNowPlayingInfoCenter + remote commands
│   ├── Settings.swift             # UserDefaults wrapper
│   ├── URLRouter.swift            # Scope checking, external URL handling
│   ├── Assets.xcassets/           # App icon
│   ├── Info.plist
│   └── JS/
│       ├── MediaBridge.js         # Injected: communicates playback state back to Swift
│       └── DurationExtractor.js   # Injected: extracts video duration from DOM
├── README.md
├── PLAN.md
└── Makefile                       # build / archive / dmg targets
```

### Key Technical Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | AppKit | Full control over tab bar, WebView lifecycle. SwiftUI's WebView story is weak. |
| Web Engine | WKWebView | Ships with macOS, zero bundle size, works with YouTube, supports Google SSO |
| Storage | SQLite (direct) | No dependencies, fast, simple schema |
| Tab suspension | Dealloc WKWebView | Most aggressive memory savings. YouTube restores state from its own cookies/localStorage |
| Cookie persistence | Default WKWebsiteDataStore | Survives app relaunch, shared across tabs |

---

## V2+ — Future Features

### Video Queue / Watch Later (Local)
- Sidebar panel (toggle with Cmd+Shift+L or button)
- Add current video to queue (keyboard shortcut + button)
- Persistent queue stored in SQLite
- Drag to reorder
- Queue auto-plays next video when current finishes
- Queue persists across app restarts

### YouTube Enhancer-style Features
- Playback speed controls (custom speeds beyond YouTube's UI)
- Auto-skip intros/outros (via SponsorBlock API)
- Custom CSS injection (hide YouTube elements like comments, shorts shelf)
- Always-on theater mode
- Volume boost beyond 100%
- All implemented as injected JS/CSS — no extension system needed

### Download Support
- Download button in toolbar
- Uses `yt-dlp` bundled or as a dependency
- Choose quality
- Download to ~/Movies/YTApp/ or configurable location
- Download manager panel showing progress

### History Sync
- iCloud CloudKit or simple file-based sync
- Sync history + queue across Macs

### Picture-in-Picture
- Native macOS PiP support (WKWebView supports this)
- Button to pop out video into floating PiP window

### Keyboard Shortcuts (Enhanced)
- Vim-style navigation (optional)
- Customizable shortcuts

---

## Build & Run (V1)

```bash
# Build
xcodebuild -project YTApp.xcodeproj -scheme YTApp -configuration Release

# Run
open build/Release/YTApp.app

# Create DMG
hdiutil create -volname "YTApp" -srcfolder build/Release/YTApp.app -ov YTApp.dmg
```

---

## Open Questions / Risks
1. **WKWebView + YouTube quality**: Should be fine (it's Safari's engine) but need to verify: 4K playback, VP9/AV1 codec support, HDR. Safari historically lags Chrome on VP9.
2. **Third-party cookie changes**: WebKit is aggressive about ITP (Intelligent Tracking Prevention). Google SSO should work since we navigate to google.com directly, but worth testing early.
3. **Media keys conflict**: If Safari or Chrome is also running, media keys might route to the wrong app. Need to test `MPRemoteCommandCenter` priority.
4. **Tab suspension aggressiveness**: 5 min default might be too aggressive if someone has a video paused. Should probably exempt tabs with active/paused video — only suspend tabs showing non-video pages or completed videos.
