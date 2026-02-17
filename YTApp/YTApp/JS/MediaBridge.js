// Injected into every YouTube page to bridge media state back to Swift
(function() {
    'use strict';

    function getVideoState() {
        const video = document.querySelector('video');
        if (!video) return null;
        return {
            paused: video.paused,
            ended: video.ended,
            duration: video.duration || 0,
            currentTime: video.currentTime || 0,
            title: document.title.replace(/ - YouTube$/, ''),
            channel: (document.querySelector('#owner #channel-name a') ||
                      document.querySelector('ytd-channel-name a') ||
                      document.querySelector('.ytp-ce-channel-title'))?.textContent?.trim() || ''
        };
    }

    // Poll and send state to Swift via message handler
    setInterval(function() {
        const state = getVideoState();
        if (state && window.webkit && window.webkit.messageHandlers.mediaBridge) {
            window.webkit.messageHandlers.mediaBridge.postMessage(JSON.stringify(state));
        }
    }, 1000);
})();
