// Intercepts YouTube's "Add to queue" action and redirects it to the native app queue.
// Must be injected at document start in capture phase to beat YouTube's own handlers.
(function() {
    'use strict';

    // Listen on capture phase to intercept before YouTube handles it
    document.addEventListener('yt-action', function(e) {
        if (!e.detail || !e.detail.actionName) return;

        if (e.detail.actionName === 'yt-add-to-playlist-command') {
            var args = e.detail.args;
            if (!args || !args.length) return;
            var cmd = args[0].addToPlaylistCommand;
            if (!cmd) return;
            if (cmd.listType !== 'PLAYLIST_EDIT_LIST_TYPE_QUEUE') return;

            // Prevent YouTube from handling it
            e.stopImmediatePropagation();
            e.preventDefault();

            var videoId = cmd.videoId;
            if (!videoId) return;

            // Try to extract title and thumbnail from the page context
            // The clicked element might have nearby metadata
            var title = '';
            var thumbnail = 'https://i.ytimg.com/vi/' + videoId + '/mqdefault.jpg';
            var channel = '';

            // Try to find the video title from the lockup/renderer near the click
            // YouTube stores metadata in renderer elements
            try {
                // Look for the most recently hovered/interacted video renderer
                var renderers = document.querySelectorAll(
                    'ytd-rich-item-renderer, ytd-compact-video-renderer, ytd-video-renderer, ytd-playlist-panel-video-renderer'
                );
                for (var i = 0; i < renderers.length; i++) {
                    var r = renderers[i];
                    var link = r.querySelector('a#video-title, a#video-title-link, span#video-title');
                    if (link) {
                        var href = link.getAttribute('href') || '';
                        if (href.indexOf(videoId) !== -1) {
                            title = (link.textContent || '').trim();
                            var ch = r.querySelector('#channel-name a, .ytd-channel-name a, ytd-channel-name a');
                            if (ch) channel = (ch.textContent || '').trim();
                            break;
                        }
                    }
                }
            } catch(ex) {}

            // If we still don't have a title, we'll fetch it from oEmbed
            var payload = {
                videoId: videoId,
                title: title,
                channel: channel,
                thumbnail: thumbnail
            };

            if (window.webkit && window.webkit.messageHandlers.queueBridge) {
                window.webkit.messageHandlers.queueBridge.postMessage(JSON.stringify(payload));
            }
        }
    }, true); // capture phase
})();
