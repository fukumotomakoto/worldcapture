// WorldCapture Web — full-page capture (injected on demand).
// Scrolls the page a viewport at a time, asks the background to grab each
// viewport via captureVisibleTab, neutralizes fixed/sticky elements after the
// first frame (so headers/footers/sidebars don't repeat — the DOM advantage
// raster screen-capture can't get), then stitches everything onto a canvas.

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
  const dpr = window.devicePixelRatio || 1;
  const viewportH = window.innerHeight;
  const fullWidth = doc.clientWidth;
  const fullHeight = Math.max(
    document.body ? document.body.scrollHeight : 0,
    doc.scrollHeight,
    document.body ? document.body.offsetHeight : 0,
    doc.offsetHeight
  );

  const originalScrollY = window.scrollY;
  const originalScrollBehavior = doc.style.scrollBehavior;
  doc.style.scrollBehavior = "auto";

  // Collect fixed/sticky elements to hide after the first frame.
  const pinned = [];
  const all = document.querySelectorAll("*");
  for (const el of all) {
    const pos = getComputedStyle(el).position;
    if (pos === "fixed" || pos === "sticky") {
      pinned.push({ el, visibility: el.style.visibility });
    }
  }
  const hidePinned = () => pinned.forEach((p) => (p.el.style.visibility = "hidden"));
  const restorePinned = () => pinned.forEach((p) => (p.el.style.visibility = p.visibility));

  try {
    const shots = [];
    let y = 0;
    let first = true;
    // Guard against runaway loops on very tall/virtualized pages.
    const maxFrames = 60;
    while (y < fullHeight && shots.length < maxFrames) {
      window.scrollTo(0, y);
      await delay(first ? 200 : 130); // let sticky settle / lazy content paint
      const dataUrl = await grab();
      shots.push({ y: Math.min(y, fullHeight - viewportH), dataUrl });
      if (first) {
        hidePinned(); // header captured once; keep it out of later frames
        first = false;
      }
      y += viewportH;
      // Respect captureVisibleTab rate limits.
      await delay(150);
    }

    const canvas = document.createElement("canvas");
    canvas.width = Math.round(fullWidth * dpr);
    canvas.height = Math.round(fullHeight * dpr);
    const ctx = canvas.getContext("2d");
    for (const shot of shots) {
      const img = await loadImage(shot.dataUrl);
      ctx.drawImage(img, 0, Math.round(shot.y * dpr));
    }
    const finalDataUrl = canvas.toDataURL("image/png");
    await browser.runtime.sendMessage({ cmd: "final", image: finalDataUrl });
  } finally {
    restorePinned();
    doc.style.scrollBehavior = originalScrollBehavior;
    window.scrollTo(0, originalScrollY);
  }
})();
