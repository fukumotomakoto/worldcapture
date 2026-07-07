// WorldCapture Web — full-page capture (injected on demand).
//
// DOM-aware capture:
//  1) Neutralize position:fixed → absolute and position:sticky → static so
//     headers/footers/sidebars render ONCE in document flow and scroll away
//     (no repeated bars, no lost sidebars — the thing raster can't do).
//  2) Keep full devicePixelRatio for sharpness; cap the captured height at
//     Safari's ~16384px canvas limit (≈8 screens at 2×, matching GoFullPage).
//     Infinite feeds are truncated, not downscaled into blur.
//  3) Pre-scroll (bounded) to trigger lazy-load within the captured range, then
//     scroll top→bottom, captureVisibleTab each viewport, stitch.

(async () => {
  const delay = (ms) => new Promise((r) => setTimeout(r, ms));

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
  const fullWidth = doc.clientWidth;
  const dpr = window.devicePixelRatio || 1;

  const docHeight = () =>
    Math.max(
      document.body ? document.body.scrollHeight : 0,
      doc.scrollHeight,
      document.body ? document.body.offsetHeight : 0,
      doc.offsetHeight
    );

  // Safari canvas per-dimension safe cap (~16384; stay under).
  const MAX_DIM = 16000;
  const maxCaptureHeight = Math.floor(MAX_DIM / dpr); // in CSS px
  const maxScreens = Math.max(1, Math.floor(maxCaptureHeight / viewportH));

  const originalScrollY = window.scrollY;
  const originalScrollBehavior = doc.style.scrollBehavior;
  doc.style.scrollBehavior = "auto";

  // Neutralize fixed/sticky so they render once and scroll with the document.
  const neutralized = [];
  for (const el of document.querySelectorAll("*")) {
    const pos = getComputedStyle(el).position;
    if (pos === "fixed" || pos === "sticky") {
      neutralized.push({ el, prev: el.style.position, prio: el.style.getPropertyPriority("position") });
      el.style.setProperty("position", pos === "fixed" ? "absolute" : "static", "important");
    }
  }
  const restore = () =>
    neutralized.forEach(({ el, prev, prio }) => {
      if (prev) el.style.setProperty("position", prev, prio);
      else el.style.removeProperty("position");
    });

  try {
    // Phase 1: bounded pre-scroll to trigger lazy-load within the captured range.
    window.scrollTo(0, 0);
    await delay(150);
    for (let i = 1; i <= maxScreens; i++) {
      window.scrollTo(0, i * viewportH);
      await delay(180);
      if (window.scrollY + viewportH >= docHeight()) break; // reached real bottom
    }
    const fullHeight = Math.min(docHeight(), maxScreens * viewportH);

    const canvas = document.createElement("canvas");
    canvas.width = Math.round(fullWidth * dpr);
    canvas.height = Math.round(fullHeight * dpr);
    const ctx = canvas.getContext("2d");

    // Phase 2: capture top→bottom, stitch 1:1 (canvas dpr == capture dpr → sharp).
    window.scrollTo(0, 0);
    await delay(160);
    let y = 0;
    while (y < fullHeight) {
      const drawY = Math.min(y, fullHeight - viewportH);
      window.scrollTo(0, drawY);
      await delay(120);
      const img = await loadImage(await grab());
      ctx.drawImage(
        img,
        0,
        Math.round(drawY * dpr),
        Math.round(fullWidth * dpr),
        Math.round(viewportH * dpr)
      );
      y += viewportH;
      await delay(150); // respect captureVisibleTab rate limits
    }

    restore();
    doc.style.scrollBehavior = originalScrollBehavior;
    window.scrollTo(0, originalScrollY);

    const finalDataUrl = canvas.toDataURL("image/png");
    await browser.runtime.sendMessage({ cmd: "final", image: finalDataUrl });
  } catch (e) {
    restore();
    doc.style.scrollBehavior = originalScrollBehavior;
    window.scrollTo(0, originalScrollY);
    throw e;
  }
})();
