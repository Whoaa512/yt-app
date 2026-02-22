(function() {
    'use strict';
    if (window.YTApp) return;

    // ── Event Bus ──────────────────────────────────────────────
    const listeners = {};      // event → [callback]
    const pluginShortcuts = {}; // key → {label, callback, pluginId}

    function on(event, callback) {
        if (!listeners[event]) listeners[event] = [];
        listeners[event].push(callback);
    }

    function off(event, callback) {
        if (!listeners[event]) return;
        listeners[event] = listeners[event].filter(fn => fn !== callback);
    }

    function emit(event, data) {
        for (const fn of (listeners[event] || [])) {
            try { fn(data); } catch(e) { console.error(`[YTApp] Plugin error on '${event}':`, e); }
        }
    }

    // Called from Swift to dispatch events to plugins
    window.__ytAppDispatchEvent = function(event, data) {
        emit(event, data);
    };

    // Called from Swift to check if a plugin handles a shortcut
    window.__ytAppPluginShortcut = function(key) {
        const entry = pluginShortcuts[key];
        if (entry) {
            try { entry.callback(); } catch(e) { console.error(`[YTApp] Shortcut error '${key}':`, e); }
            return true;
        }
        return false;
    };

    // Called from Swift to get registered shortcuts for help modal
    window.__ytAppGetPluginShortcuts = function() {
        const result = {};
        for (const [key, entry] of Object.entries(pluginShortcuts)) {
            result[key] = { label: entry.label, pluginId: entry.pluginId };
        }
        return JSON.stringify(result);
    };

    // ── Swift Bridge ───────────────────────────────────────────
    function postMessage(type, payload) {
        if (window.webkit && window.webkit.messageHandlers.pluginBridge) {
            window.webkit.messageHandlers.pluginBridge.postMessage(
                JSON.stringify({ type: type, payload: payload || {} })
            );
        }
    }

    // Async bridge: post message and wait for response
    let pendingCallbacks = {};
    let callId = 0;

    function postMessageAsync(type, payload) {
        return new Promise(function(resolve) {
            const id = ++callId;
            pendingCallbacks[id] = resolve;
            const msg = { type: type, payload: payload || {}, callId: id };
            window.webkit.messageHandlers.pluginBridge.postMessage(JSON.stringify(msg));
            // Timeout after 5s
            setTimeout(function() {
                if (pendingCallbacks[id]) {
                    pendingCallbacks[id](undefined);
                    delete pendingCallbacks[id];
                }
            }, 5000);
        });
    }

    // Called from Swift to resolve async calls
    window.__ytAppResolveCall = function(id, result) {
        if (pendingCallbacks[id]) {
            pendingCallbacks[id](result);
            delete pendingCallbacks[id];
        }
    };

    // ── Injected CSS tracking ──────────────────────────────────
    let cssCounter = 0;

    // ── Public API ─────────────────────────────────────────────
    window.YTApp = {
        // Event system
        on: on,
        off: off,
        emit: emit,

        // Register a keyboard shortcut
        registerShortcut: function(key, label, callback, pluginId) {
            pluginShortcuts[key] = { label: label, callback: callback, pluginId: pluginId || 'unknown' };
        },

        // Register a command (invokable from command palette later)
        registerCommand: function(name, handler, pluginId) {
            postMessage('registerCommand', { name: name, pluginId: pluginId || 'unknown' });
            on('command:' + name, handler);
        },

        // UI methods
        ui: {
            notify: function(message, type) {
                postMessage('notify', { message: message, type: type || 'info' });
            },

            injectCSS: function(css) {
                const id = '__ytapp-css-' + (++cssCounter);
                const style = document.createElement('style');
                style.id = id;
                style.textContent = css;
                (document.head || document.documentElement).appendChild(style);
                return id;
            },

            removeCSS: function(id) {
                const el = document.getElementById(id);
                if (el) el.remove();
            },

            // Show a toast notification overlay
            toast: function(message, duration) {
                const d = duration || 3000;
                const toast = document.createElement('div');
                toast.style.cssText = [
                    'position:fixed', 'bottom:80px', 'left:50%', 'transform:translateX(-50%)',
                    'background:rgba(0,0,0,0.85)', 'color:#fff', 'padding:8px 20px',
                    'border-radius:8px', 'font:13px/1.4 -apple-system,sans-serif',
                    'z-index:2147483647', 'pointer-events:none',
                    'box-shadow:0 4px 12px rgba(0,0,0,0.3)',
                    'transition:opacity 0.3s', 'opacity:0'
                ].join(';');
                toast.textContent = message;
                document.body.appendChild(toast);
                requestAnimationFrame(function() { toast.style.opacity = '1'; });
                setTimeout(function() {
                    toast.style.opacity = '0';
                    setTimeout(function() { toast.remove(); }, 300);
                }, d);
            },

            // Badge overlay on an element
            badge: function(selector, text, color) {
                const el = document.querySelector(selector);
                if (!el) return;
                el.style.position = el.style.position || 'relative';
                const b = document.createElement('span');
                b.className = '__ytapp-badge';
                b.textContent = text;
                b.style.cssText = 'position:absolute;top:-6px;right:-6px;background:' +
                    (color || '#f5c518') + ';color:#000;font:bold 10px/1 sans-serif;' +
                    'padding:2px 5px;border-radius:8px;z-index:999;';
                el.appendChild(b);
            }
        },

        // Tab management
        tabs: {
            open: function(url) {
                postMessage('openTab', { url: url });
            },
            getCurrent: function() {
                return window.location.href;
            },
            navigate: function(url) {
                postMessage('navigate', { url: url });
            }
        },

        // Queue management
        queue: {
            add: function(videoId, metadata) {
                postMessage('queueAdd', {
                    videoId: videoId,
                    title: (metadata && metadata.title) || '',
                    channel: (metadata && metadata.channel) || '',
                    duration: (metadata && metadata.duration) || ''
                });
            },
            list: function() {
                return postMessageAsync('queueList');
            },
            clear: function() {
                postMessage('queueClear');
            },
            playNext: function() {
                postMessage('queuePlayNext');
            }
        },

        // Per-plugin persistent storage (backed by UserDefaults via Swift)
        storage: {
            get: function(pluginId, key, defaultValue) {
                return postMessageAsync('storageGet', { pluginId: pluginId, key: key, defaultValue: defaultValue });
            },
            set: function(pluginId, key, value) {
                postMessage('storageSet', { pluginId: pluginId, key: key, value: value });
            },
            getAll: function(pluginId) {
                return postMessageAsync('storageGetAll', { pluginId: pluginId });
            }
        },

        // Video control
        video: {
            play: function() {
                var v = document.querySelector('video');
                if (v) v.play();
            },
            pause: function() {
                var v = document.querySelector('video');
                if (v) v.pause();
            },
            toggle: function() {
                var v = document.querySelector('video');
                if (v) { v.paused ? v.play() : v.pause(); }
            },
            seek: function(time) {
                var v = document.querySelector('video');
                if (v) v.currentTime = time;
            },
            seekRelative: function(delta) {
                var v = document.querySelector('video');
                if (v) v.currentTime = Math.max(0, v.currentTime + delta);
            },
            setRate: function(rate) {
                var v = document.querySelector('video');
                if (v) v.playbackRate = rate;
                postMessage('setRate', { rate: rate });
            },
            getState: function() {
                var v = document.querySelector('video');
                if (!v) return null;
                return {
                    paused: v.paused,
                    ended: v.ended,
                    currentTime: v.currentTime,
                    duration: v.duration,
                    playbackRate: v.playbackRate,
                    title: document.querySelector('#info h1 yt-formatted-string')?.textContent || document.title,
                    channel: document.querySelector('#channel-name a')?.textContent || ''
                };
            },
            // Get current video ID
            getVideoId: function() {
                var params = new URLSearchParams(window.location.search);
                return params.get('v');
            }
        },

        // Page utilities
        page: {
            isWatch: function() { return window.location.pathname === '/watch'; },
            isHome: function() { return window.location.pathname === '/'; },
            isSearch: function() { return window.location.pathname === '/results'; },
            isChannel: function() { return /^\/@|^\/channel\/|^\/c\//.test(window.location.pathname); },
            isShorts: function() { return window.location.pathname.startsWith('/shorts'); },
            getSearchQuery: function() { return new URLSearchParams(window.location.search).get('search_query'); },
            waitForElement: function(selector, timeout) {
                return new Promise(function(resolve) {
                    var el = document.querySelector(selector);
                    if (el) { resolve(el); return; }
                    var to = timeout || 10000;
                    var obs = new MutationObserver(function() {
                        var el = document.querySelector(selector);
                        if (el) { obs.disconnect(); resolve(el); }
                    });
                    obs.observe(document.body || document.documentElement, { childList: true, subtree: true });
                    setTimeout(function() { obs.disconnect(); resolve(null); }, to);
                });
            }
        },

        // Plugin metadata (populated by Swift before each plugin loads)
        _currentPlugin: null,

        // Convenience: scoped API for current plugin
        scoped: function(pluginId) {
            return {
                on: on,
                off: off,
                emit: emit,
                storage: {
                    get: function(key, def) { return window.YTApp.storage.get(pluginId, key, def); },
                    set: function(key, val) { window.YTApp.storage.set(pluginId, key, val); },
                    getAll: function() { return window.YTApp.storage.getAll(pluginId); }
                },
                registerShortcut: function(key, label, cb) {
                    window.YTApp.registerShortcut(key, label, cb, pluginId);
                },
                registerCommand: function(name, handler) {
                    window.YTApp.registerCommand(name, handler, pluginId);
                },
                ui: window.YTApp.ui,
                tabs: window.YTApp.tabs,
                queue: window.YTApp.queue,
                video: window.YTApp.video,
                page: window.YTApp.page
            };
        }
    };

    // Emit a ready event once DOM is available
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            emit('domReady', {});
        });
    } else {
        setTimeout(function() { emit('domReady', {}); }, 0);
    }
})();
