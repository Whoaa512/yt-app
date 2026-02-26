# Feature Ideas

## Delight Gaps

### 🎨 Visual Polish

- **Loading progress bar** — Thin colored bar (Safari-style) showing page load progress. Zero loading feedback today. ~50 LOC.
- **Favicon in tabs** — Tabs are text-only. Favicons make scanning instant.
- **Smooth tab transitions** — Tab switches, sidebar open/close are all instant/jarring. Add NSAnimationContext throughout.
- **Dark mode white-flash prevention** — Dark placeholder/overlay during navigations to prevent white flash between pages.

### 🎵 Playback Feel

- **Now-playing title in toolbar** — Show title/channel of playing video without tab-hunting.
- **Visual now-playing indicator** — Pulsing audio icon or waveform on the active tab to show which tab is playing.
- **Seek/scrub from native toolbar** — Only play/pause and ±10s today. No scrubbing.
- **Native volume control** — No volume slider. YouTube's built-in one is tiny.

### ⌨️ UX / Interaction

- **Find-in-page (Cmd+F)** — Standard expectation for any browser-like app.
- **Drag-to-reorder tabs** — Tabs are buttons in a stack, no drag reordering.
- **New tab page** — Curated page (recent history, queue, subscriptions grid) instead of bare youtube.com.
- **Download video button** — yt-dlp integration. Native "Download" button/shortcut.
- **PiP toggle shortcut** — Already configured in TabManager, just needs a keybind + button.
- **Toast notifications** — Visual confirmation for queue add, speed change, etc. ~80 LOC.

### 💾 Data & Continuity

- **Continue watching** — Save playback position in history for resuming later.
- **Search history / autocomplete** — Address bar suggestions from history.
- **Import/export queue** — Queue is ephemeral in UserDefaults. No way to save/share playlists.

### 🏗️ System Integration

- **Handoff / Universal Clipboard** — Pick up on iPhone where you left off.
- **Share Sheet** — Native macOS share menu for current URL.
- **Spotlight integration** — History searchable from Spotlight.

### Priority Order (impact vs effort)

| # | Feature | Effort |
|---|---------|--------|
| 1 | Loading progress bar | ~50 LOC |
| 2 | Toast notifications | ~80 LOC |
| 3 | Now-playing title in toolbar | ~40 LOC |
| 4 | Favicon in tabs | ~60 LOC |
| 5 | PiP toggle shortcut | ~20 LOC |
| 6 | Dark mode white-flash prevention | ~30 LOC |
| 7 | Find-in-page | ~40 LOC |
| 8 | Visual now-playing indicator | ~50 LOC |
| 9 | Download video button | ~100 LOC |
| 10 | Continue watching | ~80 LOC |
| 11 | Smooth tab transitions | ~60 LOC |
| 12 | Native volume control | ~80 LOC |
| 13 | Drag-to-reorder tabs | ~150 LOC |
| 14 | Search history / autocomplete | ~120 LOC |
| 15 | New tab page | ~200 LOC |
| 16 | Seek/scrub toolbar | ~100 LOC |
| 17 | Share Sheet | ~40 LOC |
| 18 | Import/export queue | ~80 LOC |
| 19 | Handoff | ~60 LOC |
| 20 | Spotlight integration | ~100 LOC |

## Native Queue Management

Intercept YouTube's built-in "Add to queue" action and manage the queue natively in the app instead.

### Discovery

YouTube fires internal events when videos are added to the queue:

- **`yt-add-to-playlist-command`** — fired via `yt-action` event with `listType: "PLAYLIST_EDIT_LIST_TYPE_QUEUE"`, includes `videoId` and `openMiniplayer: true`
- **`yt-lockup-requested`** — includes `videoIds` array of queued videos
- **`yt-playlist-data-updated`** — fires when queue contents change

These are standard DOM custom events on the document, catchable via `addEventListener`.

### Approach

1. **Intercept**: Listen for `yt-action` events where `actionName === "yt-add-to-playlist-command"` and the list type is `PLAYLIST_EDIT_LIST_TYPE_QUEUE`
2. **Prevent default**: Call `stopPropagation()` / `stopImmediatePropagation()` on the event (capture phase) to prevent YouTube's miniplayer queue from opening
3. **Extract**: Pull `videoId` (and any title/thumbnail metadata) from the event payload
4. **Bridge to Swift**: Post the video info to a `messageHandler` (e.g. `queueBridge`)
5. **Native queue UI**: Manage queue state in Swift — sidebar or panel showing queued videos, drag to reorder, remove, play next
6. **Playback**: When current video ends, auto-navigate to next video in queue

### Open Questions

- Can we reliably `stopImmediatePropagation` before YouTube's own handler runs? (Need capture phase, registered early)
- Should we also hook the right-click context menu "Add to queue" option?
- Queue persistence across sessions?
- Queue UI: sidebar vs floating panel vs toolbar dropdown?
