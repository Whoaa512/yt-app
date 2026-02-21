# Feature Ideas

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
