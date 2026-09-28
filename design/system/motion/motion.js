/* Contrast helpers ported from lib/core/service_theme.dart, so the static
   renditions resolve accent labels the way the app does, in both themes.
   Elements opt in with data attributes:
     data-ontint="<color token>"  data-surface="<color token>" (default surface)
     data-alpha="<tint alpha, dark>" data-alpha-light="<tint alpha, light>"
     data-on="<color token>"      -> foregroundOn(fill) as the text colour */
(function () {
  var probe;
  function rgb(token) {
    if (!probe) {
      probe = document.createElement('span');
      probe.style.display = 'none';
      document.documentElement.appendChild(probe);
    }
    probe.style.color = 'var(--' + token + ')';
    var m = getComputedStyle(probe).color.match(/[\d.]+/g) || [0, 0, 0, 1];
    return { r: +m[0], g: +m[1], b: +m[2], a: m[3] === undefined ? 1 : +m[3] };
  }
  function lin(c) { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
  function lum(c) { return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b); }
  function ratio(a, b) { var hi = Math.max(a, b), lo = Math.min(a, b); return (hi + 0.05) / (lo + 0.05); }
  function blend(fg, a, bg) {
    return { r: fg.r * a + bg.r * (1 - a), g: fg.g * a + bg.g * (1 - a), b: fg.b * a + bg.b * (1 - a) };
  }
  function toHsl(c) {
    var r = c.r / 255, g = c.g / 255, b = c.b / 255, max = Math.max(r, g, b), min = Math.min(r, g, b);
    var h = 0, s = 0, l = (max + min) / 2, d = max - min;
    if (d) {
      s = d / (1 - Math.abs(2 * l - 1));
      h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
      h *= 60; if (h < 0) h += 360;
    }
    return { h: h, s: s, l: l };
  }
  function fromHsl(o) {
    var c = (1 - Math.abs(2 * o.l - 1)) * o.s, x = c * (1 - Math.abs((o.h / 60) % 2 - 1)), m = o.l - c / 2;
    var p = o.h < 60 ? [c, x, 0] : o.h < 120 ? [x, c, 0] : o.h < 180 ? [0, c, x] : o.h < 240 ? [0, x, c] : o.h < 300 ? [x, 0, c] : [c, 0, x];
    return { r: (p[0] + m) * 255, g: (p[1] + m) * 255, b: (p[2] + m) * 255 };
  }
  var INK = { r: 17, g: 24, b: 39 }, WHITE = { r: 255, g: 255, b: 255 };
  function css(c) { return 'rgb(' + Math.round(c.r) + ', ' + Math.round(c.g) + ', ' + Math.round(c.b) + ')'; }
  function foregroundOn(bg) {
    var l = lum(bg);
    return ratio(lum(INK), l) >= ratio(1, l) ? INK : WHITE;
  }
  function onTint(accent, surface, alpha) {
    var bg = blend(accent, alpha, surface), bl = lum(bg);
    if (ratio(lum(accent), bl) >= 4.6) return accent;
    var darken = bl > 0.5, hsl = toHsl(accent);
    for (var step = 1; step <= 24; step++) {
      var p = step / 24;
      var l = darken ? hsl.l * (1 - p) : hsl.l + (1 - hsl.l) * p;
      var cand = fromHsl({ h: hsl.h, s: hsl.s, l: Math.min(1, Math.max(0, l)) });
      if (ratio(lum(cand), bl) >= 4.6) return cand;
    }
    return foregroundOn(bg);
  }
  function isLight() { return document.documentElement.getAttribute('data-theme') === 'light'; }
  function refresh() {
    var light = isLight();
    document.querySelectorAll('[data-ontint]').forEach(function (el) {
      var a = parseFloat((light && el.dataset.alphaLight) || el.dataset.alpha || '0');
      el.style.color = css(onTint(rgb(el.dataset.ontint), rgb(el.dataset.surface || 'surface'), a));
    });
    document.querySelectorAll('[data-on]').forEach(function (el) {
      el.style.color = css(foregroundOn(rgb(el.dataset.on)));
    });
  }
  window.Cupola = { onTint: onTint, foregroundOn: foregroundOn, refresh: refresh };
  function boot() {
    refresh();
    new MutationObserver(refresh).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'class', 'style'] });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
