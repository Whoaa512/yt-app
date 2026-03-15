(function() {
    'use strict';

    let isFullscreen = false;
    let fullscreenEl = null;

    function fireFullscreenChange() {
        document.dispatchEvent(new Event('fullscreenchange', {bubbles: true}));
        document.dispatchEvent(new Event('webkitfullscreenchange', {bubbles: true}));
    }

    Element.prototype.requestFullscreen = function(opts) {
        isFullscreen = true;
        fullscreenEl = this;
        window.webkit.messageHandlers.fullscreenBridge.postMessage({action: 'enter'});
        fireFullscreenChange();
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
