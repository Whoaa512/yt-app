// SponsorBlock plugin for YTApp
// Uses the public SponsorBlock API to fetch and skip sponsored segments.

(function() {
    'use strict';
    const API_BASE = 'https://sponsor.ajay.app/api';
    let segments = [];
    let enabled = true;
    let skipTimer = null;
    let currentVideoId = null;
    let barSegments = [];

    // Categories to skip (configurable via plugin settings)
    const DEFAULT_CATEGORIES = ['sponsor', 'selfpromo', 'interaction'];

    async function fetchSegments(videoId) {
        segments = [];
        removeBarOverlay();
        if (!videoId) return;

        try {
            const cats = JSON.stringify(DEFAULT_CATEGORIES);
            const resp = await fetch(
                `${API_BASE}/skipSegments?videoID=${videoId}&categories=${encodeURIComponent(cats)}`
            );
            if (!resp.ok) return;
            const data = await resp.json();
            segments = data.map(s => ({
                start: s.segment[0],
                end: s.segment[1],
                category: s.category,
                uuid: s.UUID
            }));
            if (segments.length > 0) {
                plugin.ui.toast(`SponsorBlock: ${segments.length} segment(s) found`, 2000);
                renderBarOverlay();
            }
        } catch(e) {
            console.error('[SponsorBlock] Fetch error:', e);
        }
    }

    function startSkipLoop() {
        if (skipTimer) return;
        skipTimer = setInterval(function() {
            if (!enabled || segments.length === 0) return;
            const video = document.querySelector('video');
            if (!video || video.paused) return;
            const t = video.currentTime;
            for (const seg of segments) {
                if (t >= seg.start && t < seg.end - 0.3) {
                    video.currentTime = seg.end;
                    plugin.ui.toast(`Skipped ${seg.category} (${Math.round(seg.end - seg.start)}s)`, 2000);
                    break;
                }
            }
        }, 500);
    }

    function stopSkipLoop() {
        if (skipTimer) { clearInterval(skipTimer); skipTimer = null; }
    }

    // Render colored segments on YouTube's progress bar
    function renderBarOverlay() {
        removeBarOverlay();
        const video = document.querySelector('video');
        const bar = document.querySelector('.ytp-progress-bar');
        if (!video || !bar || !video.duration) return;

        const duration = video.duration;
        for (const seg of segments) {
            const el = document.createElement('div');
            el.className = '__sb-segment';
            const left = (seg.start / duration * 100).toFixed(2);
            const width = ((seg.end - seg.start) / duration * 100).toFixed(2);
            el.style.cssText = `position:absolute;bottom:0;height:100%;left:${left}%;width:${width}%;z-index:40;pointer-events:none;`;

            // Color by category
            switch(seg.category) {
                case 'sponsor': el.style.background = 'rgba(0, 212, 0, 0.5)'; break;
                case 'selfpromo': el.style.background = 'rgba(230, 230, 0, 0.5)'; break;
                case 'interaction': el.style.background = 'rgba(204, 0, 255, 0.5)'; break;
                default: el.style.background = 'rgba(128, 128, 128, 0.4)';
            }
            bar.style.position = 'relative';
            bar.appendChild(el);
            barSegments.push(el);
        }
    }

    function removeBarOverlay() {
        for (const el of barSegments) el.remove();
        barSegments = [];
    }

    // Toggle function exposed globally for the keyboard shortcut
    window.__sbToggle = function() {
        enabled = !enabled;
        plugin.ui.toast(`SponsorBlock: ${enabled ? 'ON' : 'OFF'}`, 2000);
    };

    // ── Initialize ─────────────────────────────────────────────

    // `plugin` is the scoped YTApp API injected by the plugin loader
    plugin.on('navigate', function(data) {
        const url = new URL(data.url);
        const videoId = url.searchParams.get('v');
        if (videoId && videoId !== currentVideoId) {
            currentVideoId = videoId;
            fetchSegments(videoId);
        }
    });

    plugin.on('videoState', function(state) {
        if (!state.paused && !state.ended) {
            startSkipLoop();
        }
    });

    plugin.on('videoEnd', function() {
        stopSkipLoop();
    });

    // Initial check if already on a watch page
    const params = new URLSearchParams(window.location.search);
    const vid = params.get('v');
    if (vid) {
        currentVideoId = vid;
        fetchSegments(vid);
        startSkipLoop();
    }
})();
