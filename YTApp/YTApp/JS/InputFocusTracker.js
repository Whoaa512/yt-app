(function() {
    if (window.__ytInputFocusTrackerInstalled) return;
    window.__ytInputFocusTrackerInstalled = true;

    function isInputElement(el) {
        if (!el) return false;
        var tag = el.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
        if (el.isContentEditable) return true;
        if (el.getAttribute && el.getAttribute('role') === 'textbox') return true;
        return false;
    }

    function notify(focused) {
        try {
            webkit.messageHandlers.inputFocusChanged.postMessage({ focused: focused });
        } catch(e) {}
    }

    document.addEventListener('focusin', function(e) {
        if (isInputElement(e.target)) notify(true);
    }, true);

    document.addEventListener('focusout', function(e) {
        if (isInputElement(e.target)) {
            setTimeout(function() {
                if (!isInputElement(document.activeElement)) notify(false);
            }, 0);
        }
    }, true);

    if (isInputElement(document.activeElement)) notify(true);
})();
