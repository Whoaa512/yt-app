(function() {
    'use strict';
    if (window.__ytLinkHintsInstalled) return;
    window.__ytLinkHintsInstalled = true;

    const HINT_CHARS = 'sadfjklewcmpgh';
    let active = false;
    let hints = [];
    let typedChars = '';
    let overlay = null;
    let newTab = false;

    function generateHintStrings(count) {
        const strings = [];
        if (count === 0) return strings;
        const len = Math.max(1, Math.ceil(Math.log(count) / Math.log(HINT_CHARS.length)));
        function generate(prefix, depth) {
            if (depth === 0) {
                if (strings.length < count) strings.push(prefix);
                return;
            }
            for (let i = 0; i < HINT_CHARS.length && strings.length < count; i++) {
                generate(prefix + HINT_CHARS[i], depth - 1);
            }
        }
        generate('', len);
        return strings;
    }

    function getClickableElements() {
        const selectors = [
            'a[href]',
            'button:not([disabled])',
            'input:not([type="hidden"]):not([disabled])',
            'select:not([disabled])',
            'textarea:not([disabled])',
            '[role="button"]',
            '[role="link"]',
            '[role="tab"]',
            '[role="menuitem"]',
            '[tabindex]:not([tabindex="-1"])',
            'ytd-rich-item-renderer',
            'ytd-compact-video-renderer',
            'ytd-video-renderer',
            'ytd-grid-video-renderer',
            'ytd-playlist-video-renderer',
            '#video-title',
            'yt-formatted-string[has-link-only_]',
            '.ytp-button',
        ];

        const all = document.querySelectorAll(selectors.join(','));
        const visible = [];
        const seen = new Set();

        for (const el of all) {
            const rect = el.getBoundingClientRect();
            if (rect.width === 0 || rect.height === 0) continue;
            if (rect.bottom < 0 || rect.top > window.innerHeight) continue;
            if (rect.right < 0 || rect.left > window.innerWidth) continue;

            // Dedupe overlapping elements — use center point
            const key = Math.round(rect.left / 20) + ',' + Math.round(rect.top / 20);
            if (seen.has(key)) continue;
            seen.add(key);

            visible.push({ el, rect });
        }
        return visible;
    }

    function showHints(openInNewTab) {
        if (active) { removeHints(); return; }
        newTab = openInNewTab || false;
        const elements = getClickableElements();
        if (elements.length === 0) return;

        const hintStrings = generateHintStrings(elements.length);
        overlay = document.createElement('div');
        overlay.id = '__yt-link-hints-overlay';
        overlay.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;z-index:2147483647;pointer-events:none;';

        hints = [];
        for (let i = 0; i < elements.length; i++) {
            const { el, rect } = elements[i];
            const hintStr = hintStrings[i];

            const label = document.createElement('div');
            label.className = '__yt-hint-label';
            label.textContent = hintStr.toUpperCase();
            label.style.cssText = `
                position: fixed;
                left: ${rect.left + 2}px;
                top: ${rect.top + 2}px;
                background: linear-gradient(135deg, #f5c518, #e6b800);
                color: #000;
                font: bold 11px/1 'SF Mono', 'Menlo', monospace;
                padding: 2px 4px;
                border-radius: 3px;
                pointer-events: none;
                z-index: 2147483647;
                box-shadow: 0 1px 3px rgba(0,0,0,0.4);
                letter-spacing: 0.5px;
            `;
            label.dataset.hint = hintStr;
            overlay.appendChild(label);
            hints.push({ el, label, hint: hintStr });
        }

        document.body.appendChild(overlay);
        active = true;
        typedChars = '';
    }

    function removeHints() {
        if (overlay && overlay.parentNode) {
            overlay.parentNode.removeChild(overlay);
        }
        overlay = null;
        hints = [];
        active = false;
        typedChars = '';
        newTab = false;
    }

    function filterHints() {
        let remaining = 0;
        for (const h of hints) {
            if (h.hint.startsWith(typedChars)) {
                h.label.style.display = '';
                // Highlight matched portion
                const matched = typedChars.toUpperCase();
                const rest = h.hint.substring(typedChars.length).toUpperCase();
                h.label.innerHTML = `<span style="opacity:0.5">${matched}</span>${rest}`;
                remaining++;
            } else {
                h.label.style.display = 'none';
            }
        }

        if (remaining === 0) {
            removeHints();
            return;
        }

        // Exact match
        const match = hints.find(h => h.hint === typedChars);
        if (match) {
            activateElement(match.el);
            removeHints();
        }
    }

    function activateElement(el) {
        if (newTab && el.tagName === 'A' && el.href) {
            window.webkit.messageHandlers.newTab.postMessage(el.href);
            return;
        }

        // For video renderers, find the title link
        if (el.tagName.startsWith('YTD-') && el.tagName.includes('RENDERER')) {
            const link = el.querySelector('a#video-title-link, a#video-title, a#thumbnail');
            if (link) {
                if (newTab) {
                    window.webkit.messageHandlers.newTab.postMessage(link.href);
                } else {
                    link.click();
                }
                return;
            }
        }

        el.focus();
        el.click();
    }

    function handleKeyDown(e) {
        if (!active) return;

        if (e.key === 'Escape') {
            e.preventDefault();
            e.stopImmediatePropagation();
            removeHints();
            return;
        }

        if (e.key === 'Backspace') {
            e.preventDefault();
            e.stopImmediatePropagation();
            typedChars = typedChars.slice(0, -1);
            if (typedChars.length === 0) {
                // Reset all hints to visible
                for (const h of hints) {
                    h.label.style.display = '';
                    h.label.textContent = h.hint.toUpperCase();
                }
            } else {
                filterHints();
            }
            return;
        }

        const ch = e.key.toLowerCase();
        if (HINT_CHARS.includes(ch)) {
            e.preventDefault();
            e.stopImmediatePropagation();
            typedChars += ch;
            filterHints();
        }
    }

    // Listen for activation messages from Swift
    window.__ytShowLinkHints = function(openInNewTab) {
        showHints(openInNewTab);
    };
    window.__ytHideLinkHints = function() {
        removeHints();
    };
    window.__ytLinkHintsActive = function() {
        return active;
    };

    document.addEventListener('keydown', handleKeyDown, true);
})();
