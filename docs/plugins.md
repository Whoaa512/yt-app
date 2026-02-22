# YTApp Plugins

Plugins extend YTApp with custom behavior — inject CSS, run JS, add keyboard shortcuts, and hook into YouTube events. Inspired by [pi's extension system](https://github.com/badlogic/pi-mono).

## Quick Start

1. Create a plugin folder:
   ```bash
   mkdir -p ~/.ytapp/plugins/my-plugin
   ```

2. Add a `manifest.json`:
   ```json
   {
     "name": "My Plugin",
     "version": "1.0.0",
     "description": "Does something cool",
     "content_scripts": [
       {
         "js": ["content.js"],
         "inject_at": "document_end"
       }
     ]
   }
   ```

3. Write your script (`content.js`):
   ```js
   // `plugin` is auto-injected — a scoped YTApp API for your plugin
   plugin.on('navigate', function(data) {
       console.log('Navigated to:', data.url);
   });

   plugin.registerShortcut('s', 'Do something', function() {
       plugin.ui.toast('Hello from my plugin!');
   });
   ```

4. YTApp auto-discovers plugins on launch and hot-reloads on file changes.

## Plugin Structure

```
~/.ytapp/plugins/
└── my-plugin/
    ├── manifest.json    # Required — metadata and configuration
    ├── content.js       # JS injected into pages
    ├── style.css        # CSS injected into pages
    └── ...
```

## manifest.json

```json
{
  "name": "My Plugin",
  "version": "1.0.0",
  "description": "What this plugin does",
  "author": "Your Name",

  "content_scripts": [
    {
      "js": ["content.js"],
      "css": ["style.css"],
      "inject_at": "document_end",
      "url_patterns": ["*youtube.com/watch*"]
    }
  ],

  "styles": ["global.css"],

  "shortcuts": {
    "s": {
      "action": "click",
      "value": "#subscribe-button button",
      "label": "Subscribe"
    },
    "gp": {
      "action": "navigate",
      "value": "https://www.youtube.com/feed/subscriptions",
      "label": "Go to subscriptions"
    }
  },

  "permissions": ["videoState", "navigate", "queue"],

  "settings": [
    {
      "key": "autoSkip",
      "label": "Auto-skip sponsors",
      "type": "bool",
      "default": "true"
    }
  ]
}
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | ✅ | Display name |
| `version` | | Semver string |
| `description` | | Shown in plugin manager |
| `author` | | Author name |
| `content_scripts` | | JS/CSS to inject |
| `styles` | | Top-level CSS files (always injected) |
| `shortcuts` | | Keyboard shortcuts (see below) |
| `permissions` | | Events this plugin needs |
| `settings` | | User-configurable settings schema |

### Content Scripts

| Field | Default | Description |
|-------|---------|-------------|
| `js` | `[]` | JS files to inject |
| `css` | `[]` | CSS files to inject |
| `inject_at` | `"document_end"` | `"document_start"` or `"document_end"` |
| `url_patterns` | all pages | Glob patterns to match URLs |

### Shortcut Actions

| Action | Value | Description |
|--------|-------|-------------|
| `click` | CSS selector | Click the first matching element |
| `js` | JavaScript code | Evaluate JS in the page |
| `navigate` | URL | Load URL in the active tab |

## Plugin API (`plugin`)

Every JS content script receives a `plugin` variable — a scoped API tied to your plugin ID.

### Events

```js
plugin.on('navigate', function(data) {
    // data.url, data.title
});

plugin.on('videoState', function(state) {
    // state.paused, state.ended, state.currentTime,
    // state.duration, state.title, state.channel
});

plugin.on('videoEnd', function(data) {
    // Video finished playing
});

plugin.on('domReady', function() {
    // DOM is ready
});

plugin.on('reload', function() {
    // Plugins were hot-reloaded
});
```

### UI

```js
plugin.ui.toast('Hello!', 3000);                   // Toast notification
plugin.ui.notify('Message', 'info');                // Native notification (info|warning|error)
const id = plugin.ui.injectCSS('body { ... }');     // Inject CSS, returns ID
plugin.ui.removeCSS(id);                            // Remove injected CSS
plugin.ui.badge('#element', '3', '#f5c518');        // Badge overlay
```

### Tabs

```js
plugin.tabs.open('https://youtube.com/...');   // Open in new tab
plugin.tabs.navigate('https://...');           // Load in current tab
plugin.tabs.getCurrent();                       // Current URL string
```

### Queue

```js
plugin.queue.add('dQw4w9WgXcQ', {
    title: 'Never Gonna Give You Up',
    channel: 'Rick Astley',
    duration: '3:33'
});
const items = await plugin.queue.list();
plugin.queue.clear();
plugin.queue.playNext();
```

### Video

```js
plugin.video.play();
plugin.video.pause();
plugin.video.toggle();
plugin.video.seek(120);           // Seek to 2:00
plugin.video.seekRelative(-10);   // Back 10s
plugin.video.setRate(2.0);
plugin.video.getVideoId();        // Current video ID
const state = plugin.video.getState();
// { paused, ended, currentTime, duration, playbackRate, title, channel }
```

### Storage (persistent, per-plugin)

```js
await plugin.storage.set('myKey', 'myValue');
const val = await plugin.storage.get('myKey', 'default');
const all = await plugin.storage.getAll();
```

### Shortcuts

```js
plugin.registerShortcut('s', 'Subscribe', function() {
    document.querySelector('#subscribe-button button')?.click();
});
```

### Commands

```js
plugin.registerCommand('my-command', function() {
    // Invokable from command palette (future)
});
```

### Page Utilities

```js
YTApp.page.isWatch();    // true on /watch
YTApp.page.isHome();     // true on /
YTApp.page.isSearch();   // true on /results
YTApp.page.isChannel();  // true on /@..., /channel/..., /c/...
YTApp.page.isShorts();   // true on /shorts/...
YTApp.page.getSearchQuery();

// Wait for an element to appear (useful for SPA navigation)
const el = await YTApp.page.waitForElement('#subscribe-button', 5000);
```

### Inter-plugin Communication

```js
// Plugin A
plugin.emit('my-plugin:data-ready', { items: [...] });

// Plugin B
plugin.on('my-plugin:data-ready', function(data) {
    console.log(data.items);
});
```

## Managing Plugins

- **Menu:** Plugins → Manage Plugins… (`⌘,`)
- **Enable/disable** plugins without removing them
- **Open Plugin Folder** to browse `~/.ytapp/plugins/`
- **Reload** (`⌘⇧R`) to pick up changes immediately
- **Hot reload**: File changes in the plugins directory are detected automatically

## Examples

See [`examples/plugins/`](../examples/plugins/) for working plugins:

| Plugin | Description |
|--------|-------------|
| `hide-shorts` | CSS-only — removes Shorts from YouTube |
| `sponsorblock` | Fetches and auto-skips sponsored segments |
| `custom-css` | Blank stylesheet for user customization |

## Tips

- Use `plugin.ui.toast()` for debug feedback — it's non-intrusive
- `YTApp.page.waitForElement()` is essential for YouTube's SPA — elements load asynchronously
- Namespace your events: `plugin.emit('my-plugin:event-name', data)`
- Plugin shortcuts run after built-in shortcuts — avoid conflicts with `f`, `t`, `x`, `?`, etc.
- CSS-only plugins are the simplest — no JS needed, just `styles` in the manifest
