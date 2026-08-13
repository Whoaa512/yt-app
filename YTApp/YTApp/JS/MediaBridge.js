// Injected into every YouTube page to bridge media state back to Swift
(function() {
    'use strict';

    function getChannel() {
        const el = document.querySelector('#owner #channel-name a') ||
                   document.querySelector('ytd-channel-name a') ||
                   document.querySelector('.ytp-ce-channel-title');
        let name = el?.textContent?.trim() || '';
        if (!name) {
            // Collab videos hide ytd-channel-name; the new layout renders
            // "Primary Channel and N more" in #upload-info's attributed string.
            const attr = document.querySelector('#owner #upload-info yt-attributed-string');
            name = attr?.textContent?.trim().replace(/\s+and \d+ more$/, '') || '';
        }
        return name;
    }

    // All channels on the video (collab videos have several). Names live in
    // ytd-watch-flexy's polymer data (avatar-stack dialog), which stays fresh
    // across SPA navigation, unlike window.ytInitialData. Cached per URL —
    // the data tree is large.
    let channelsCache = { url: null, names: [] };
    function getChannels(primary) {
        if (channelsCache.url === location.href) return channelsCache.names;
        const names = [];
        (function walk(o, depth) {
            if (!o || typeof o !== 'object' || depth > 25 || names.length > 20) return;
            const text = o.avatarViewModel?.accessibilityText;
            if (text) {
                const m = text.match(/^(.*?)\.? Go to channel\.?$/);
                if (m && !names.includes(m[1])) names.push(m[1]);
            }
            for (const k in o) walk(o[k], depth + 1);
        })(document.querySelector('ytd-watch-flexy')?.data, 0);
        if (primary && !names.includes(primary)) names.unshift(primary);
        if (names.length) channelsCache = { url: location.href, names };
        return names;
    }

    function getVideoState() {
        const video = document.querySelector('video');
        if (!video) return null;
        const channel = getChannel();
        return {
            paused: video.paused,
            ended: video.ended,
            duration: video.duration || 0,
            currentTime: video.currentTime || 0,
            pip: document.pictureInPictureElement === video,
            title: document.title.replace(/ - YouTube$/, ''),
            channel: channel,
            channels: getChannels(channel)
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
