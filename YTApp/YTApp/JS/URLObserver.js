// Observes YouTube SPA navigation and reports URL changes to Swift
(function() {
    'use strict';
    let lastURL = location.href;

    function reportURL() {
        const url = location.href;
        if (url !== lastURL) {
            lastURL = url;
            if (window.webkit && window.webkit.messageHandlers.urlChanged) {
                window.webkit.messageHandlers.urlChanged.postMessage(url);
            }
        }
    }

    // YouTube fires yt-navigate-finish on SPA navigation
    window.addEventListener('yt-navigate-finish', reportURL);

    // Also intercept pushState/replaceState for robustness
    const origPush = history.pushState;
    const origReplace = history.replaceState;
    history.pushState = function() {
        origPush.apply(this, arguments);
        reportURL();
    };
    history.replaceState = function() {
        origReplace.apply(this, arguments);
        reportURL();
    };
    window.addEventListener('popstate', reportURL);

    // Theater mode observation — use MutationObserver on ytd-watch-flexy, but only one
    let theaterObserver = null;
    let observedElement = null;

    function setupTheaterObserver() {
        const page = document.querySelector('ytd-watch-flexy');
        if (!page || page === observedElement) return;

        if (theaterObserver) theaterObserver.disconnect();
        observedElement = page;

        function reportTheater() {
            // YouTube uses the 'theater' attribute (boolean) on ytd-watch-flexy
            const isTheater = page.hasAttribute('theater');
            if (window.webkit && window.webkit.messageHandlers.theaterChanged) {
                window.webkit.messageHandlers.theaterChanged.postMessage(isTheater);
            }
        }

        theaterObserver = new MutationObserver(reportTheater);
        theaterObserver.observe(page, { attributes: true, attributeFilter: ['theater'] });

        // Report current state immediately
        reportTheater();
    }

    // Also listen for YouTube's own theater mode event
    document.addEventListener('yt-set-theater-mode-enabled', function(e) {
        const enabled = e && e.detail && e.detail.enabled;
        if (window.webkit && window.webkit.messageHandlers.theaterChanged) {
            window.webkit.messageHandlers.theaterChanged.postMessage(!!enabled);
        }
    }, true);

    // Try to attach observer when page is ready and on each navigation
    window.addEventListener('yt-navigate-finish', function() {
        setTimeout(setupTheaterObserver, 500);
    });

    // Wait for initial page load
    if (document.querySelector('ytd-watch-flexy')) {
        setupTheaterObserver();
    } else {
        const bodyObs = new MutationObserver(function() {
            if (document.querySelector('ytd-watch-flexy')) {
                bodyObs.disconnect();
                setupTheaterObserver();
            }
        });
        bodyObs.observe(document.documentElement, { childList: true, subtree: true });
        setTimeout(function() { bodyObs.disconnect(); }, 15000);
    }
})();
