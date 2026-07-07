// WorldCapture Web — full-page capture (injected on demand).
//
// The DOM-aware, three-phase capture that beats native raster:
//  1) Pre-scroll to the bottom to trigger lazy-loading / infinite feeds, and
//     re-measure the REAL page height (it grows as content loads).
//  2) Pick a pixel ratio that keeps the stitched canvas within Safari's
//     ~16384px per-dimension limit (else toDataURL returns blank on long pages);
//     short pages stay at full devicePixelRatio for sharpness.
//  3) Scroll top→bottom, captureVisibleTab each viewport, stitch onto the canvas.
//     Only SHORT fixed bars (nav/footer/floating buttons) are hidden after the
//     first frame — tall fixed/sticky sidebars are kept so their content isn't lost.

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

  const docHeight = () =>
    Math.max(
      document.body ? document.body.scrollHeight : 0,
      doc.scrollHeight,
      document.body ? document.body.offsetHeight : 0,
      doc.offsetHeight
    );

  const originalScrollY = window.scrollY;
  const originalScrollBehavior = doc.style.scrollBehavior;
  doc.style.scrollBehavior = "auto";

  // Cap the number of viewports so a truly-infinite feed still terminates.
  const MAX_FRAMES = 40;
  // Safari canvas per-dimension safe cap (limit is ~16384; stay under it).
  const MAX_DIM = 16000;

  try {
    // ---- Phase 1: pre-scroll to load lazy content, measure the real height ----
    let measuredHeight = docHeight();
    let prev = -1;
    let stable = 0;
    for (let i = 0; i < MAX_FRAMES; i++) {
      window.scrollTo(0, docHeight());
      await delay(200);
      const h = docHeight();
      if (h === prev) {
        if (++stable >= 2) break; // height settled → everything loaded
      } else {
        stable = 0;
      }
      prev = h;
    }
    measuredHeight = docHeight();

    // ---- Phase 2: choose a pixel ratio that keeps the canvas valid ----
    let dpr = window.devicePixelRatio || 1;
    dpr = Math.min(dpr, MAX_DIM / measuredHeight, MAX_DIM / Math.max(1, fullWidth));
    dpr = Math.max(dpr, 0.5);
    let fullHeight = measuredHeight;
    if (fullHeight * dpr > MAX_DIM) fullHeight = Math.floor(MAX_DIM / dpr); // hard truncate on extreme pages

    const canvas = document.createElement("canvas");
    canvas.width = Math.round(fullWidth * dpr);
    canvas.height = Math.round(fullHeight * dpr);
    const ctx = canvas.getContext("2d");

    // Elements to hide after the first frame: only SHORT position:fixed bars,
    // so tall fixed/sticky sidebars keep their (unique) content.
    const pinned = [];
    for (const el of document.querySelectorAll("*")) {
      if (getComputedStyle(el).position !== "fixed") continue;
      const rect = el.getBoundingClientRect();
      if (rect.height > 0 && rect.height < viewportH * 0.6) {
        pinned.push({ el, visibility: el.style.visibility });
      }
    }

    // ---- Phase 3: capture top→bottom and stitch ----
    window.scrollTo(0, 0);
    await delay(200);
    let y = 0;
    let first = true;
    while (y < fullHeight) {
      const drawY = Math.min(y, fullHeight - viewportH);
      window.scrollTo(0, drawY);
      await delay(first ? 160 : 120);
      const dataUrl = await grab();
      const img = await loadImage(dataUrl);
      ctx.drawImage(
        img,
        0,
        Math.round(drawY * dpr),
        Math.round(fullWidth * dpr),
        Math.round(viewportH * dpr)
      );
      if (first) {
        pinned.forEach((p) => (p.el.style.visibility = "hidden"));
        first = false;
      }
      y += viewportH;
      await delay(150); // respect captureVisibleTab rate limits
    }

    pinned.forEach((p) => (p.el.style.visibility = p.visibility));
    const finalDataUrl = canvas.toDataURL("image/png");
    await browser.runtime.sendMessage({ cmd: "final", image: finalDataUrl });
  } finally {
    doc.style.scrollBehavior = originalScrollBehavior;
    window.scrollTo(0, originalScrollY);
  }
})();
