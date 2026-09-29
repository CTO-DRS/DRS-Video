/// YouTube in-page ad killer (v1.11.0).
///
/// Network blocking alone cannot fully silence YouTube because most of
/// its ad renditions are served from youtube.com / googlevideo.com — the
/// very hosts that also serve the videos — and are rendered inside the
/// page DOM. This class ships a compact user-script that the built-in
/// browser injects into EVERY frame at document-start. The script:
///
///   1. hides ad units with CSS (masthead, search results, feed rows,
///      banner promos, companion overlays),
///   2. auto-clicks every "Skip" button the moment it appears
///      (English + Arabic aria-labels covered),
///   3. ends in-player ads almost instantly by seeking the ad video to
///      its final frame (the classic fast-forward technique) whenever
///      the player reports an ad break,
///   4. keeps watching the DOM via a MutationObserver + lightweight
///      400ms interval so late-loaded ads are caught too.
///
/// The script self-guards against double installation
/// (`__drsAdKillInstalled`) and can be paused at runtime by setting
/// `window.__drsAdKill = false` (used when the user toggles the shield
/// off mid-session). Every DOM/network action is wrapped in try/catch —
/// the script must NEVER break page functionality.
class YtAdKiller {
  YtAdKiller._();

  /// DOM containers that carry ads (hidden via injected CSS).
  static const List<String> hideSelectors = [
    '.video-ads',
    '.ytp-ad-module',
    '.ytp-ad-player-overlay',
    '.ytp-ad-overlay-container',
    '.ytp-ad-text',
    '.ytp-ad-image',
    '.ytp-ad-badge',
    '.ytp-ad-preview-container',
    '#masthead-ad',
    '#player-ads',
    'ytd-display-ad-renderer',
    'ytd-ad-slot-renderer',
    'ytd-infeed-ad-renderer',
    'ytd-compact-promoted-video-renderer',
    'ytd-promoted-sparkles-web-renderer',
    'ytd-promoted-video-renderer',
    'ytd-promoted-playlist-renderer',
    'ytd-banner-promo-renderer',
    'ytd-statement-banner-renderer',
    'ytd-mealbar-promoted-renderer',
    'ytm-promoted-video-renderer',
    'ytd-ads',
    'ytd-rich-item-renderer[is-ad]',
    '.ytd-primetime-promo-renderer',
  ];

  /// Buttons that skip/close ads (auto-clicked on sight).
  static const List<String> skipSelectors = [
    '.ytp-ad-skip-button',
    '.ytp-ad-skip-button-modern',
    '.ytp-skip-ad-button',
    '.ytp-ad-skip-button-slot button',
    '.ytp-ad-skip-button-container button',
    'button[class*="ytp-ad-skip"]',
    'button[class*="skip-ad"]',
    '.videoAdUiSkipButton',
    '.ytm-ad-skip-button',
    'button[aria-label*="skip"]',
    'button[aria-label*="Skip"]',
    'button[aria-label*="تخطي"]',
    '.ytp-ad-overlay-close-button',
  ];

  /// The user-script source (plain ES5 — no template literals, no
  /// arrow functions — so it survives any WebView engine).
  static String get js => '''
(function(){
  if (window.__drsAdKillInstalled) { window.__drsAdKill = true; return; }
  window.__drsAdKillInstalled = true;
  window.__drsAdKill = true;
  var SKIP = '${skipSelectors.join(',')}';
  var HIDE = '${hideSelectors.join(',')}';
  var css = document.createElement('style');
  css.id = 'drs-ad-css';
  css.textContent = HIDE + '{display:none !important;visibility:hidden !important;height:0 !important;}';
  function injectCss(){
    try {
      if (!document.getElementById('drs-ad-css')) {
        (document.head || document.documentElement).appendChild(css);
      }
    } catch (e) {}
  }
  var busy = false;
  function tick(){
    if (window.__drsAdKill === false) return;
    if (busy) return;
    busy = true;
    try { injectCss(); } catch (e) {}
    try {
      var skip = document.querySelectorAll(SKIP);
      for (var i = 0; i < skip.length; i++) {
        try { skip[i].click(); } catch (e) {}
      }
      var mp = document.querySelector(
        '#movie_player.ad-showing, #movie_player.ad-interrupting, ' +
        '.html5-video-player.ad-showing, .html5-video-player.ad-interrupting');
      if (mp) {
        var v = mp.querySelector('video.html5-main-video') ||
                mp.querySelector('video');
        if (v && v.duration && isFinite(v.duration) && v.duration > 0) {
          try { v.currentTime = v.duration; } catch (e) {}
        }
      }
    } catch (e) {}
    busy = false;
  }
  function start(){
    injectCss();
    tick();
    setInterval(tick, 400);
    try {
      var mo = new MutationObserver(function(){ setTimeout(tick, 60); });
      mo.observe(document.documentElement, { childList: true, subtree: true });
    } catch (e) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else { start(); }
})();
''';
}
