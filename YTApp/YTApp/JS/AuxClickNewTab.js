// Intercept middle-click / three-finger tap on links → open in new tab.
// Uses both mouseup and auxclick for maximum compatibility with WKWebView.
(function() {
    'use strict';
    function handleMiddleClick(e) {
        if (e.button !== 1) return;
        const link = e.target.closest('a[href]');
        if (!link) return;
        const href = link.href;
        if (!href || href.startsWith('javascript:')) return;
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        window.webkit.messageHandlers.newTab.postMessage(href);
    }
    document.addEventListener('mouseup', handleMiddleClick, true);
    document.addEventListener('auxclick', handleMiddleClick, true);
    // Suppress middle-click default behavior (auto-scroll)
    document.addEventListener('mousedown', function(e) {
        if (e.button === 1 && e.target.closest('a[href]')) {
            e.preventDefault();
        }
    }, true);
})();
