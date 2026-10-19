(function() {
    'use strict';

    let isFullscreen = false;
    let fullscreenEl = null;

    // Real API fires asynchronously; sync dispatch runs before YouTube has
    // finished its own state update and it ignores the change.
    function fireFullscreenChange() {
        const target = fullscreenEl || document;
        setTimeout(function() {
            target.dispatchEvent(new Event('fullscreenchange', {bubbles: true}));
            target.dispatchEvent(new Event('webkitfullscreenchange', {bubbles: true}));
        }, 0);
    }

    // YouTube ignores DOM fullscreenchange under the Safari UA; its player
    // exposes setFauxFullscreen for hosts that manage fullscreen themselves.
    // Faux mode flips the player's state but the watch page never lays it
    // out over the viewport, so pin it ourselves.
    const style = document.createElement('style');
    style.textContent = 'html.ytapp-fs{overflow:hidden!important}html.ytapp-fs #movie_player.ytp-fullscreen{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;z-index:9999!important;background:#000}html.ytapp-fs #masthead-container,html.ytapp-fs #secondary,html.ytapp-fs #below,html.ytapp-fs ytd-mini-guide-renderer,html.ytapp-fs tp-yt-app-drawer{display:none!important}';
    function setFauxFullscreen(on) {
        document.documentElement.classList.toggle('ytapp-fs', on);
        if (on && !style.isConnected) document.head.appendChild(style);
        const p = document.querySelector('#movie_player');
        if (p && typeof p.setFauxFullscreen === 'function') p.setFauxFullscreen(on);
        setTimeout(function() { window.dispatchEvent(new Event('resize')); }, 50);
    }

    Element.prototype.requestFullscreen = function(opts) {
        if (isFullscreen) return Promise.resolve();
        isFullscreen = true;
        fullscreenEl = this;
        window.webkit.messageHandlers.fullscreenBridge.postMessage({action: 'enter'});
        fireFullscreenChange();
        setFauxFullscreen(true);
        return Promise.resolve();
    };

    if (Element.prototype.webkitRequestFullscreen) {
        Element.prototype.webkitRequestFullscreen = Element.prototype.requestFullscreen;
    }
    if (Element.prototype.webkitRequestFullScreen) {
        Element.prototype.webkitRequestFullScreen = Element.prototype.requestFullscreen;
    }

    Document.prototype.exitFullscreen = function() {
        if (isFullscreen) {
            isFullscreen = false;
            fullscreenEl = null;
            window.webkit.messageHandlers.fullscreenBridge.postMessage({action: 'exit'});
            fireFullscreenChange();
            setFauxFullscreen(false);
        }
        return Promise.resolve();
    };

    Document.prototype.webkitExitFullscreen = Document.prototype.exitFullscreen;
    Document.prototype.webkitCancelFullScreen = Document.prototype.exitFullscreen;

    Object.defineProperty(Document.prototype, 'fullscreenElement', {
        get: function() { return fullscreenEl; }
    });
    Object.defineProperty(Document.prototype, 'webkitFullscreenElement', {
        get: function() { return fullscreenEl; }
    });
    Object.defineProperty(Document.prototype, 'webkitCurrentFullScreenElement', {
        get: function() { return fullscreenEl; }
    });
    Object.defineProperty(Document.prototype, 'fullscreenEnabled', {
        get: function() { return true; }
    });
    Object.defineProperty(Document.prototype, 'webkitFullscreenEnabled', {
        get: function() { return true; }
    });
    Object.defineProperty(Document.prototype, 'webkitIsFullScreen', {
        get: function() { return isFullscreen; }
    });
})();
