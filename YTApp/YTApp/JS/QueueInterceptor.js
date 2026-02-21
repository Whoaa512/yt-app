// Intercepts YouTube's "Add to queue" action and redirects it to the native app queue.
// Must be injected at document start in capture phase to beat YouTube's own handlers.
(function() {
    'use strict';

    // Track the last right-clicked or hovered renderer for context
    var lastInteractedRenderer = null;

    // Capture right-click context — the menu item click happens later
    document.addEventListener('contextmenu', function(e) {
        var el = e.target;
        while (el && el !== document) {
            if (el.tagName && el.tagName.toLowerCase().match(
                /^(ytd-rich-item-renderer|ytd-compact-video-renderer|ytd-video-renderer|ytd-playlist-panel-video-renderer|ytd-grid-video-renderer|ytd-reel-item-renderer|ytd-rich-grid-media)$/
            )) {
                lastInteractedRenderer = el;
                break;
            }
            el = el.parentElement;
        }
    }, true);

    // Also capture clicks on menu items (the 3-dot menu)
    document.addEventListener('click', function(e) {
        var el = e.target;
        // Walk up to find if we're inside a renderer
        var depth = 0;
        while (el && el !== document && depth < 20) {
            if (el.tagName && el.tagName.toLowerCase().match(
                /^(ytd-rich-item-renderer|ytd-compact-video-renderer|ytd-video-renderer|ytd-playlist-panel-video-renderer|ytd-grid-video-renderer|ytd-reel-item-renderer|ytd-rich-grid-media)$/
            )) {
                lastInteractedRenderer = el;
                break;
            }
            depth++;
            el = el.parentElement;
        }
    }, true);

    function extractFromRenderer(r, videoId) {
        var result = { title: '', channel: '', duration: '', viewCount: '', publishedText: '', thumbnail: '' };
        if (!r) return result;

        // Title — try multiple strategies
        var titleEl = r.querySelector('#video-title') ||
                      r.querySelector('a#video-title-link') ||
                      r.querySelector('h3 a') ||
                      r.querySelector('span#video-title') ||
                      r.querySelector('[id="video-title"]') ||
                      r.querySelector('yt-formatted-string#video-title');
        if (titleEl) result.title = (titleEl.textContent || titleEl.getAttribute('title') || '').trim();

        // Also try aria-label on the title link which often has full title
        if (!result.title) {
            var ariaEl = r.querySelector('a[aria-label]');
            if (ariaEl) {
                var aria = ariaEl.getAttribute('aria-label') || '';
                // aria-label often contains "Title by Channel X views Y ago Duration"
                // Just take it as a fallback
                if (aria.length > 5) result.title = aria.split(' by ')[0] || aria;
            }
        }

        // Channel
        var chEl = r.querySelector('#channel-name a') ||
                   r.querySelector('ytd-channel-name a') ||
                   r.querySelector('ytd-channel-name #text') ||
                   r.querySelector('#text.ytd-channel-name') ||
                   r.querySelector('.ytd-channel-name a');
        if (chEl) result.channel = (chEl.textContent || '').trim();

        // Duration
        var durEl = r.querySelector('ytd-thumbnail-overlay-time-status-renderer span') ||
                    r.querySelector('span.ytd-thumbnail-overlay-time-status-renderer') ||
                    r.querySelector('.badge-shape-wiz__text') ||
                    r.querySelector('#time-status span');
        if (durEl) {
            var d = (durEl.textContent || '').trim();
            if (d.match(/\d/)) result.duration = d;
        }

        // Metadata: view count + published date
        var metaSpans = r.querySelectorAll(
            '#metadata-line span, .inline-metadata-item, ' +
            'ytd-video-meta-block span, #metadata span'
        );
        for (var j = 0; j < metaSpans.length; j++) {
            var text = (metaSpans[j].textContent || '').trim();
            if (!text || text.length < 2) continue;
            if (text.match(/view/i) || text.match(/watching/i)) {
                result.viewCount = text;
            } else if (text.match(/ago|streamed|premier|Premiered/i) ||
                       text.match(/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/i)) {
                result.publishedText = text;
            }
        }

        // Thumbnail
        var thumbImg = r.querySelector('ytd-thumbnail img') ||
                       r.querySelector('img#img') ||
                       r.querySelector('yt-image img');
        if (thumbImg && thumbImg.src && thumbImg.src.indexOf('ytimg') !== -1) {
            result.thumbnail = thumbImg.src;
        }

        return result;
    }

    function findRendererByVideoId(videoId) {
        // Strategy 1: Use tracked renderer
        if (lastInteractedRenderer) {
            var links = lastInteractedRenderer.querySelectorAll('a[href]');
            for (var i = 0; i < links.length; i++) {
                if ((links[i].getAttribute('href') || '').indexOf(videoId) !== -1) {
                    return lastInteractedRenderer;
                }
            }
        }

        // Strategy 2: Search all renderers
        var selectors = [
            'ytd-rich-item-renderer', 'ytd-compact-video-renderer', 'ytd-video-renderer',
            'ytd-playlist-panel-video-renderer', 'ytd-grid-video-renderer',
            'ytd-reel-item-renderer', 'ytd-rich-grid-media'
        ];
        var renderers = document.querySelectorAll(selectors.join(', '));
        for (var i = 0; i < renderers.length; i++) {
            var rLinks = renderers[i].querySelectorAll('a[href*="' + videoId + '"]');
            if (rLinks.length > 0) return renderers[i];
        }

        return null;
    }

    document.addEventListener('yt-action', function(e) {
        if (!e.detail || !e.detail.actionName) return;

        if (e.detail.actionName === 'yt-add-to-playlist-command') {
            var args = e.detail.args;
            if (!args || !args.length) return;
            var cmd = args[0].addToPlaylistCommand;
            if (!cmd) return;
            if (cmd.listType !== 'PLAYLIST_EDIT_LIST_TYPE_QUEUE') return;

            e.stopImmediatePropagation();
            e.preventDefault();

            var videoId = cmd.videoId;
            if (!videoId) return;

            var renderer = findRendererByVideoId(videoId);
            var meta = extractFromRenderer(renderer, videoId);

            var payload = {
                videoId: videoId,
                title: meta.title,
                channel: meta.channel,
                thumbnail: meta.thumbnail || ('https://i.ytimg.com/vi/' + videoId + '/mqdefault.jpg'),
                duration: meta.duration,
                viewCount: meta.viewCount,
                publishedText: meta.publishedText
            };

            if (window.webkit && window.webkit.messageHandlers.queueBridge) {
                window.webkit.messageHandlers.queueBridge.postMessage(JSON.stringify(payload));
            }

            // Clear tracked renderer
            lastInteractedRenderer = null;
        }
    }, true);
})();
