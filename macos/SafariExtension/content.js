// WorldCapture Web — full-page capture (injected on demand).
//
// Single-pass, DOM-aware capture (mirrors GoFullPage's proven path, with its
// weak spots fixed):
//  1) ONE scroll traversal top→bottom. The scroll itself triggers lazy-load;
//     each step settles via rAF + a short delay before grabbing.
//  2) Fixed/sticky are neutralized selectively so each renders exactly once:
//     headers on the first frame, footers on the last, everything hidden on the
//     middle frames — never repeated, never lost. FIXED elements are hidden with
//     display:none (out of flow → no reflow, and children can't override the
//     hide); STICKY with visibility:hidden (in flow → keep its space). Fixed/
//     sticky are RE-SCANNED every frame so elements that only become fixed after
//     scrolling (back-to-top bars, floating share rails) are caught too.
//  3) DPR is MEASURED from the first captured frame (image.width ÷ CSS width),
//     not trusted from devicePixelRatio, so zoom/emulation stay sharp and 1:1.
//  4) Height is capped at Safari's per-dimension canvas limit; the tail of an
//     infinite feed is truncated rather than downscaled into blur.

(async () => {
  const delay = (ms) => new Promise((r) => setTimeout(r, ms));
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const settle = async () => {
    await raf();
    await raf();
    await delay(80); // let lazy images decode / layout settle in this viewport
  };

  // Claim this tab's capture job. Every later message carries the ID, so the
  // background can refuse frames from a stale or cancelled job.
  const begin = await browser.runtime.sendMessage({ cmd: "begin" });
  if (!begin || !begin.jobId) return;
  const jobId = begin.jobId;

  // Grab the current viewport as a PNG data URL. The background worker owns the
  // captureVisibleTab rate-limit throttle + retry and verifies this tab is still
  // the active one before and after every grab.
  const grab = async () => {
    const r = await browser.runtime.sendMessage({ cmd: "grab", jobId });
    if (!r || !r.dataUrl) throw new Error((r && r.error) || "grab failed");
    return r.dataUrl;
  };

  const loadImage = (src) =>
    new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = src;
    });

  // Small in-page notice (no alert(): it would block the page and the extension).
  const notice = (text) => {
    try {
      const el = document.createElement("div");
      el.textContent = text;
      el.style.cssText =
        "position:fixed;z-index:2147483647;left:50%;top:16px;transform:translateX(-50%);" +
        "padding:8px 14px;border-radius:8px;background:rgba(28,28,30,.92);color:#fff;" +
        "font:13px -apple-system,system-ui,sans-serif;box-shadow:0 4px 16px rgba(0,0,0,.25)";
      document.documentElement.appendChild(el);
      setTimeout(() => el.remove(), 4000);
    } catch (_) {}
  };

  const doc = document.documentElement;
  const viewportH = window.innerHeight;
  const viewportW = window.innerWidth; // CSS width incl. any scrollbar gutter
  const fullWidth = doc.clientWidth; // content width, excludes the scrollbar

  const docHeight = () =>
    Math.max(
      document.body ? document.body.scrollHeight : 0,
      doc.scrollHeight,
      document.body ? document.body.offsetHeight : 0,
      doc.offsetHeight
    );

  // Safari canvas per-dimension safe cap (~16384; stay under). We size in CSS px
  // using the reported DPR as an estimate; the real scale is measured later.
  const MAX_DIM = 16000;
  const dprEstimate = window.devicePixelRatio || 1;
  const capHeight = Math.max(viewportH, Math.floor(MAX_DIM / dprEstimate));

  const originalScrollX = window.scrollX;
  const originalScrollY = window.scrollY;
  const originalScrollBehavior = doc.style.scrollBehavior;
  doc.style.scrollBehavior = "auto";

  // Remember every element we touch so we can restore it exactly afterward.
  const touched = new Map();
  const remember = (el) => {
    if (touched.has(el)) return;
    touched.set(el, {
      display: el.style.display,
      displayPrio: el.style.getPropertyPriority("display"),
      vis: el.style.visibility,
      visPrio: el.style.getPropertyPriority("visibility"),
    });
  };
  const hideEl = (el, isFixed) => {
    remember(el);
    if (isFixed) el.style.setProperty("display", "none", "important");
    else el.style.setProperty("visibility", "hidden", "important");
  };
  const showEl = (el) => {
    const p = touched.get(el);
    if (!p) return;
    if (p.display) el.style.setProperty("display", p.display, p.displayPrio);
    else el.style.removeProperty("display");
    if (p.vis) el.style.setProperty("visibility", p.vis, p.visPrio);
    else el.style.removeProperty("visibility");
  };
  const restore = () => touched.forEach((_p, el) => showEl(el));

  // Classify each fixed/sticky element ONCE, while it is still visible, and
  // remember it. Re-measuring later is wrong: once we hide a fixed footer with
  // display:none its rect is all zeros (top = 0), which would re-classify it as
  // a header and keep it hidden on the last frame. Elements that are not
  // rendered yet (zero-size, e.g. inside a hidden ancestor) are left alone until
  // they can be measured; elements that appear later are classified then.
  const classes = new Map(); // el -> { isFixed, footer }
  const classify = (el, pos) => {
    const known = classes.get(el);
    if (known) return known;
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) return null;
    const c = { isFixed: pos === "fixed", footer: rect.top >= viewportH * 0.6 };
    classes.set(el, c);
    return c;
  };

  // phase: "single" (page fits one frame) | "first" | "middle" | "last".
  const applyPhase = (phase) => {
    for (const el of document.querySelectorAll("*")) {
      const pos = getComputedStyle(el).position;
      if (pos !== "fixed" && pos !== "sticky" && !classes.has(el)) continue;
      const c = classify(el, pos);
      if (!c) continue;
      let hidden;
      if (phase === "single") hidden = false; // show everything, no repeats possible
      else if (phase === "first") hidden = c.footer; // headers appear once, at top
      else if (phase === "last") hidden = !c.footer; // footers appear once, at bottom
      else hidden = true; // middle frames: hide all so nothing repeats
      if (hidden) hideEl(el, c.isFixed);
      else showEl(el);
    }
  };

  // Scroll, then wait until the position stops moving (scroll-snap, smooth
  // scrolling) and read the ACTUAL position — snapping may land at 120 when we
  // asked for 100, and the frame must be placed where it really is.
  const scrollToAndSettle = async (target) => {
    window.scrollTo(originalScrollX, target);
    let last = NaN;
    let stable = 0;
    for (let i = 0; i < 40 && stable < 3; i++) {
      await raf();
      const y = window.scrollY;
      if (y === last) stable++;
      else {
        stable = 0;
        last = y;
      }
    }
    await settle();
    return window.scrollY;
  };

  try {
    // Single pass: scroll top→bottom, settling + grabbing each viewport. Height
    // is re-evaluated every step so lazy-grown pages keep going (up to the cap).
    const frames = [];
    const gaps = []; // [fromY, toY] CSS ranges no frame covered
    let covered = 0; // bottom edge (CSS px) of everything captured so far
    let prevY = -1;
    let first = true;
    let target = 0;
    let truncated = false;
    while (true) {
      let dh = Math.min(docHeight(), capHeight);
      let maxY = Math.max(0, dh - viewportH);
      const aim = Math.min(target, maxY);
      let phase = first && aim >= maxY ? "single" : first ? "first" : aim >= maxY ? "last" : "middle";
      applyPhase(phase);
      let y = await scrollToAndSettle(aim);

      // Snapped past the end of what we have (scroll-snap pulled us further than
      // asked): step back towards the last frame until we land on a position
      // that still overlaps it, so no band of the page is skipped. Smaller
      // steps mean more frames, never a hole. If nothing works, the gap is
      // recorded and reported on the result page.
      if (!first && y > covered + 0.5) {
        const quarter = Math.max(1, (y - prevY) / 4);
        for (let i = 1; i <= 3; i++) {
          const retry = await scrollToAndSettle(Math.max(prevY + 1, covered - i * quarter));
          if (retry > prevY + 0.5 && retry <= covered + 0.5) {
            y = retry;
            break;
          }
        }
      }

      dh = Math.min(docHeight(), capHeight);
      maxY = Math.max(0, dh - viewportH);
      const atBottom = y >= maxY - 0.5;
      // Landed on the bottom although we planned a middle/first frame: show the
      // footers for this, the final frame.
      if (atBottom && phase !== "last" && phase !== "single") {
        phase = first ? "single" : "last";
        applyPhase(phase);
        await settle();
      }

      // The page won't scroll any further (same position twice) before the end:
      // stop instead of stitching the same viewport again.
      if (!first && y <= prevY + 0.5) {
        truncated = true;
        break;
      }

      if (y > covered + 0.5) gaps.push([Math.round(covered), Math.round(y)]);
      frames.push({ y, dataUrl: await grab() });
      covered = Math.max(covered, y + viewportH);
      prevY = y;

      if (atBottom) {
        truncated = docHeight() > capHeight;
        break;
      }
      first = false;
      target = y + viewportH;
    }

    // Stitch. Measure the real device scale from the first frame (robust to
    // zoom/emulation), size the canvas in device pixels, draw 1:1 (sharp) at
    // each frame's ACTUAL scroll position, cropping the scrollbar gutter.
    const fullHeight = Math.min(Math.max(docHeight(), covered), capHeight);
    let scale = null;
    let canvas = null;
    let ctx = null;
    for (const f of frames) {
      const img = await loadImage(f.dataUrl);
      if (scale === null) {
        scale = viewportW > 0 ? img.width / viewportW : dprEstimate;
        canvas = document.createElement("canvas");
        canvas.width = Math.round(fullWidth * scale);
        canvas.height = Math.round(fullHeight * scale);
        ctx = canvas.getContext("2d");
      }
      const sw = Math.round(fullWidth * scale);
      const sh = Math.round(viewportH * scale);
      ctx.drawImage(img, 0, 0, sw, sh, 0, Math.round(f.y * scale), sw, sh);
    }

    restore();
    doc.style.scrollBehavior = originalScrollBehavior;
    window.scrollTo(originalScrollX, originalScrollY);

    const finalDataUrl = canvas.toDataURL("image/png");
    const r = await browser.runtime.sendMessage({
      cmd: "final",
      jobId,
      image: finalDataUrl,
      cssWidth: fullWidth,
      scale: Math.round((scale || dprEstimate) * 100) / 100,
      gaps,
      truncated,
    });
    if (!r || !r.ok) notice("WorldCapture: " + ((r && r.error) || "capture failed"));
  } catch (e) {
    restore();
    doc.style.scrollBehavior = originalScrollBehavior;
    window.scrollTo(originalScrollX, originalScrollY);
    try {
      await browser.runtime.sendMessage({ cmd: "abort", jobId });
    } catch (_) {}
    notice("WorldCapture: " + String(e && e.message ? e.message : e));
  }
})();
