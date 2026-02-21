// Injected at DOCUMENT START
// YouTube sets 'wide=1' as a session cookie which WKWebView discards on quit.
// Re-set it with an expiration so it persists.
(function() {
    'use strict';
    if ('%THEATER_ENABLED%' === 'true') {
        var exp = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toUTCString();
        document.cookie = 'wide=1;domain=youtube.com;path=/;expires=' + exp;
    }
})();
