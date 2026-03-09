(function() {
    'use strict';

    var lastRightClickedRenderer = null;

    document.addEventListener('contextmenu', function(e) {
        lastRightClickedRenderer = null;
        var el = e.target;
        while (el && el !== document) {
            if (el.tagName && el.tagName.toLowerCase().match(
                /^(ytd-rich-item-renderer|ytd-compact-video-renderer|ytd-video-renderer|ytd-playlist-panel-video-renderer|ytd-grid-video-renderer|ytd-reel-item-renderer|ytd-rich-grid-media)$/
            )) {
                lastRightClickedRenderer = el;
                break;
            }
            el = el.parentElement;
        }
    }, true);

    window.__ytGetSummarizeVideoUrl = function() {
        if (!lastRightClickedRenderer) return '';
        var link = lastRightClickedRenderer.querySelector('a[href*="/watch"]') ||
                   lastRightClickedRenderer.querySelector('a[href*="/shorts/"]');
        if (!link) return '';
        var href = link.getAttribute('href') || '';
        if (href.startsWith('/')) href = 'https://www.youtube.com' + href;
        return href;
    };
})();
