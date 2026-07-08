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

  // Grab the current viewport as a PNG data URL. The background worker owns the
  // captureVisibleTab rate-limit throttle + retry; we just await the result.
  const grab = async () => {
    const r = await browser.runtime.sendMessage({ cmd: "grab" });
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

  // Re-scan the whole DOM for fixed/sticky and hide/show per phase. A fixed
  // element's viewport rect is stable across scroll, so we can classify it as a
  // header (near top) or footer (lower viewport) on any frame.
  // phase: "single" (page fits one frame) | "first" | "middle" | "last".
  const applyPhase = (phase) => {
    for (const el of document.querySelectorAll("*")) {
      const pos = getComputedStyle(el).position;
      const isFixed = pos === "fixed";
      const isSticky = pos === "sticky";
      if (!isFixed && !isSticky) continue;
      const footer = el.getBoundingClientRect().top >= viewportH * 0.6;
      let hidden;
      if (phase === "single") hidden = false; // show everything, no repeats possible
      else if (phase === "first") hidden = footer; // headers appear once, at top
      else if (phase === "last") hidden = !footer; // footers appear once, at bottom
      else hidden = true; // middle frames: hide all so nothing repeats
      if (hidden) hideEl(el, isFixed);
      else showEl(el);
    }
  };

  window.scrollTo(0, 0);
  await raf();
  await delay(120);

  try {
    // Single pass: scroll top→bottom, settling + grabbing each viewport. Height
    // is re-evaluated every step so lazy-grown pages keep going (up to the cap).
    const frames = [];
    let y = 0;
    let first = true;
    while (true) {
      const dh = Math.min(docHeight(), capHeight);
      const atBottom = y + viewportH >= dh;
      const drawY = atBottom ? Math.max(0, dh - viewportH) : y;
      const phase = first && atBottom ? "single" : first ? "first" : atBottom ? "last" : "middle";

      applyPhase(phase);
      window.scrollTo(0, drawY);
      await settle();
      frames.push({ drawY, dataUrl: await grab() });

      if (atBottom) break;
      first = false;
      y += viewportH;
    }

    // Stitch. Measure the real device scale from the first frame (robust to
    // zoom/emulation), size the canvas in device pixels, draw 1:1 (sharp),
    // cropping the scrollbar gutter out of each frame.
    const fullHeight = Math.min(docHeight(), capHeight);
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
      ctx.drawImage(img, 0, 0, sw, sh, 0, Math.round(f.drawY * scale), sw, sh);
    }

    restore();
    doc.style.scrollBehavior = originalScrollBehavior;
    window.scrollTo(0, originalScrollY);

    const finalDataUrl = canvas.toDataURL("image/png");
    await browser.runtime.sendMessage({
      cmd: "final",
      image: finalDataUrl,
      cssWidth: fullWidth,
      scale: Math.round((scale || dprEstimate) * 100) / 100,
    });
  } catch (e) {
    restore();
    doc.style.scrollBehavior = originalScrollBehavior;
    window.scrollTo(0, originalScrollY);
    throw e;
  }
})();
