// Extract video duration as formatted string
(function() {
    const video = document.querySelector('video');
    if (!video || !video.duration || isNaN(video.duration)) return '';
    const total = Math.floor(video.duration);
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    if (h > 0) {
        return h + ':' + String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
    }
    return m + ':' + String(s).padStart(2, '0');
})();
