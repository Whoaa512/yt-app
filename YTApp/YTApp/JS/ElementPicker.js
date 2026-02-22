(function() {
    'use strict';
    if (window.__ytElementPickerInstalled) return;
    window.__ytElementPickerInstalled = true;

    let picking = false;
    let highlightEl = null;
    let lastTarget = null;

    const highlight = document.createElement('div');
    highlight.id = '__yt-element-picker-highlight';
    highlight.style.cssText = `
        position: fixed; pointer-events: none; z-index: 2147483647;
        border: 2px solid #f5c518; background: rgba(245,197,24,0.15);
        border-radius: 3px; transition: all 0.08s ease;
        display: none;
    `;

    const badge = document.createElement('div');
    badge.style.cssText = `
        position: absolute; bottom: -22px; left: 0;
        background: #f5c518; color: #000; font: bold 10px/1 'SF Mono', monospace;
        padding: 3px 6px; border-radius: 2px; white-space: nowrap;
        max-width: 400px; overflow: hidden; text-overflow: ellipsis;
    `;
    highlight.appendChild(badge);

    function bestSelector(el) {
        if (el.id) return '#' + CSS.escape(el.id);

        // Try aria-label
        const aria = el.getAttribute('aria-label');
        if (aria && aria.length < 60) {
            const tag = el.tagName.toLowerCase();
            const sel = tag + '[aria-label="' + aria.replace(/"/g, '\\"') + '"]';
            if (document.querySelectorAll(sel).length === 1) return sel;
        }

        // Try unique class combo
        if (el.classList.length > 0) {
            const tag = el.tagName.toLowerCase();
            for (const cls of el.classList) {
                const sel = tag + '.' + CSS.escape(cls);
                if (document.querySelectorAll(sel).length === 1) return sel;
            }
        }

        // Build path up
        const parts = [];
        let cur = el;
        while (cur && cur !== document.body && parts.length < 5) {
            let part = cur.tagName.toLowerCase();
            if (cur.id) {
                parts.unshift('#' + CSS.escape(cur.id));
                break;
            }
            if (cur.classList.length > 0) {
                part += '.' + Array.from(cur.classList).map(c => CSS.escape(c)).join('.');
            }
            // nth-child for disambiguation
            const parent = cur.parentElement;
            if (parent) {
                const siblings = Array.from(parent.children).filter(c => c.tagName === cur.tagName);
                if (siblings.length > 1) {
                    const idx = siblings.indexOf(cur) + 1;
                    part += ':nth-child(' + idx + ')';
                }
            }
            parts.unshift(part);
            cur = cur.parentElement;
        }
        return parts.join(' > ');
    }

    function onMouseMove(e) {
        if (!picking) return;
        const target = document.elementFromPoint(e.clientX, e.clientY);
        if (!target || target === highlight || highlight.contains(target)) return;
        lastTarget = target;

        const rect = target.getBoundingClientRect();
        highlight.style.display = 'block';
        highlight.style.left = rect.left + 'px';
        highlight.style.top = rect.top + 'px';
        highlight.style.width = rect.width + 'px';
        highlight.style.height = rect.height + 'px';
        badge.textContent = bestSelector(target);
    }

    function onClick(e) {
        if (!picking) return;
        e.preventDefault();
        e.stopImmediatePropagation();

        const sel = lastTarget ? bestSelector(lastTarget) : '';
        stopPicking();

        // Send selector back to Swift
        window.webkit.messageHandlers.elementPicked.postMessage(sel);
    }

    function onKeyDown(e) {
        if (!picking) return;
        if (e.key === 'Escape') {
            e.preventDefault();
            e.stopImmediatePropagation();
            stopPicking();
            window.webkit.messageHandlers.elementPicked.postMessage('');
        }
    }

    function startPicking() {
        if (picking) return;
        picking = true;
        document.body.appendChild(highlight);
        document.addEventListener('mousemove', onMouseMove, true);
        document.addEventListener('click', onClick, true);
        document.addEventListener('keydown', onKeyDown, true);
        document.body.style.cursor = 'crosshair';
    }

    function stopPicking() {
        picking = false;
        highlight.style.display = 'none';
        if (highlight.parentNode) highlight.parentNode.removeChild(highlight);
        document.removeEventListener('mousemove', onMouseMove, true);
        document.removeEventListener('click', onClick, true);
        document.removeEventListener('keydown', onKeyDown, true);
        document.body.style.cursor = '';
        lastTarget = null;
    }

    window.__ytStartElementPicker = startPicking;
    window.__ytStopElementPicker = stopPicking;
})();
