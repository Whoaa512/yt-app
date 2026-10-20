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
    // the data tree is large. Only walk the owner section: the full tree also
    // holds related videos/comments, whose channels would falsely match pins.
    let channelsCache = { url: null, names: [] };
    function findOwner(o, depth) {
        if (!o || typeof o !== 'object' || depth > 12) return null;
        if (o.videoSecondaryInfoRenderer) return o.videoSecondaryInfoRenderer.owner || null;
        for (const k in o) {
            if (k === 'secondaryResults') continue;
            const r = findOwner(o[k], depth + 1);
            if (r) return r;
        }
        return null;
    }
    function getChannels(primary) {
        if (channelsCache.url === location.href) return channelsCache.names;
        const names = [];
        const owner = findOwner(document.querySelector('ytd-watch-flexy')?.data, 0);
        (function walk(o, depth) {
            if (!o || typeof o !== 'object' || depth > 25 || names.length > 20) return;
            const text = o.avatarViewModel?.accessibilityText;
            if (text) {
                const m = text.match(/^(.*?)\.? Go to channel\.?$/);
                if (m && !names.includes(m[1])) names.push(m[1]);
            }
            for (const k in o) walk(o[k], depth + 1);
        })(owner, 0);
        // Polymer data can lag SPA nav; only cache once it matches the DOM owner.
        const fresh = names.length && (!primary || names.includes(primary));
        if (primary && !names.includes(primary)) names.unshift(primary);
        if (fresh) channelsCache = { url: location.href, names };
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
            playbackRate: video.playbackRate,
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
