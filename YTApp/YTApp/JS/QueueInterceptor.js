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

            var title = '';
            var thumbnail = 'https://i.ytimg.com/vi/' + videoId + '/mqdefault.jpg';
            var channel = '';
            var duration = '';
            var viewCount = '';
            var publishedText = '';

            // Extract metadata from the renderer element that contains this videoId
            try {
                var renderers = document.querySelectorAll(
                    'ytd-rich-item-renderer, ytd-compact-video-renderer, ytd-video-renderer, ' +
                    'ytd-playlist-panel-video-renderer, ytd-grid-video-renderer, ytd-reel-item-renderer'
                );
                for (var i = 0; i < renderers.length; i++) {
                    var r = renderers[i];
                    // Match by videoId in any link
                    var links = r.querySelectorAll('a[href*="' + videoId + '"]');
                    if (links.length === 0) continue;

                    // Title
                    var titleEl = r.querySelector('#video-title, a#video-title-link, h3 a, span#video-title');
                    if (titleEl) title = (titleEl.textContent || '').trim();

                    // Channel
                    var chEl = r.querySelector(
                        '#channel-name a, ytd-channel-name a, .ytd-channel-name a, ' +
                        '#text.ytd-channel-name, ytd-channel-name #text'
                    );
                    if (chEl) channel = (chEl.textContent || '').trim();

                    // Duration from overlay badge
                    var durEl = r.querySelector(
                        'span.ytd-thumbnail-overlay-time-status-renderer, ' +
                        'ytd-thumbnail-overlay-time-status-renderer span, ' +
                        '.badge-shape-wiz__text'
                    );
                    if (durEl) duration = (durEl.textContent || '').trim();

                    // Metadata line: view count + published date
                    // YouTube renders these as inline spans in #metadata-line
                    var metaSpans = r.querySelectorAll(
                        '#metadata-line span, ' +
                        '.inline-metadata-item, ' +
                        'ytd-video-meta-block span.ytd-video-meta-block'
                    );
                    for (var j = 0; j < metaSpans.length; j++) {
                        var text = (metaSpans[j].textContent || '').trim();
                        if (!text) continue;
                        if (text.match(/view/i) || text.match(/watching/i)) {
                            viewCount = text;
                        } else if (text.match(/ago|streamed|premier/i) ||
                                   text.match(/\d{1,2}\/\d{1,2}\/\d{2,4}/) ||
                                   text.match(/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/i)) {
                            publishedText = text;
                        }
                    }

                    // Higher-res thumbnail if available
                    var thumbImg = r.querySelector('img#img, yt-image img, ytd-thumbnail img');
                    if (thumbImg && thumbImg.src && thumbImg.src.indexOf('ytimg') !== -1) {
                        thumbnail = thumbImg.src;
                    }

                    break;
                }
            } catch(ex) {}

            var payload = {
                videoId: videoId,
                title: title,
                channel: channel,
                thumbnail: thumbnail,
                duration: duration,
                viewCount: viewCount,
                publishedText: publishedText
            };

            if (window.webkit && window.webkit.messageHandlers.queueBridge) {
                window.webkit.messageHandlers.queueBridge.postMessage(JSON.stringify(payload));
            }
        }
    }, true); // capture phase
})();
