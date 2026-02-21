// Intercept auxiliary clicks (middle-click / three-finger tap) on links
// and send URL to Swift for opening in a new tab.
(function() {
    document.addEventListener('auxclick', function(e) {
        if (e.button !== 1) return; // only middle button
        const link = e.target.closest('a[href]');
        if (!link) return;
        const href = link.href;
        if (!href || href.startsWith('javascript:')) return;
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        window.webkit.messageHandlers.newTab.postMessage(href);
    }, true);
})();
