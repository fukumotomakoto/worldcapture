// WorldCapture Web — background service worker.
// Orchestrates full-page capture: injects content.js, serves per-frame
// captureVisibleTab grabs, and hands the stitched PNG to the native app.

const NATIVE_APP_ID = "io.worldcapture.app.Extension";

// captureVisibleTab is hard-capped at 2 calls/sec on Chromium
// (MAX_CAPTURE_VISIBLE_TAB_CALLS_PER_SECOND); Safari's limit is undocumented, so
// we hold a ≥500ms floor between grabs and retry with back-off on any rejection
// (quota or transient). The OSS GoFullPage does neither and simply stalls.
const CAPTURE_MIN_INTERVAL_MS = 500;
const CAPTURE_MAX_ATTEMPTS = 4;
let lastCaptureAt = 0;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The most recent stitched full-page PNG, held for the result page to fetch.
let pendingResult = null;

async function activeTab() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function grabViewport(windowId) {
  for (let attempt = 0; attempt < CAPTURE_MAX_ATTEMPTS; attempt++) {
    const wait = CAPTURE_MIN_INTERVAL_MS - (Date.now() - lastCaptureAt);
    if (wait > 0) await sleep(wait);
    lastCaptureAt = Date.now();
    try {
      return await browser.tabs.captureVisibleTab(windowId, { format: "png" });
    } catch (e) {
      if (attempt === CAPTURE_MAX_ATTEMPTS - 1) throw e;
      await sleep(CAPTURE_MIN_INTERVAL_MS * (attempt + 1)); // linear back-off
    }
  }
}

browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  // From popup: begin a full-page capture of the active tab.
  if (msg.cmd === "start") {
    startCapture()
      .then((r) => sendResponse(r))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true; // keep the channel open for the async reply
  }

  // From content.js: grab the current viewport as a PNG data URL (throttled +
  // retried to respect the captureVisibleTab rate limit).
  if (msg.cmd === "grab") {
    const windowId = sender.tab ? sender.tab.windowId : undefined;
    grabViewport(windowId)
      .then((dataUrl) => sendResponse({ dataUrl }))
      .catch((e) => sendResponse({ error: String(e) }));
    return true;
  }

  // From content.js: the stitched full-page PNG is ready. Show it in the browser
  // (standalone result page) — the hand-off to the native app is then an opt-in
  // button there, not a hard dependency.
  if (msg.cmd === "final") {
    pendingResult = msg.image;
    browser.tabs
      .create({ url: browser.runtime.getURL("result.html"), active: true })
      .then(() => sendResponse({ ok: true }))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true;
  }

  // From result.js: fetch the image to display.
  if (msg.cmd === "getResult") {
    sendResponse({ image: pendingResult });
    return false;
  }

  // From result.js: user clicked "Open in WorldCapture" — hand off to native.
  if (msg.cmd === "openInApp") {
    sendToNative(msg.image || pendingResult)
      .then((r) => sendResponse(r))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true;
  }

  return false;
});

async function startCapture() {
  const tab = await activeTab();
  if (!tab || tab.id == null) return { ok: false, error: "no active tab" };
  // Injecting content.js runs its capture IIFE, which drives the scroll +
  // per-frame grabs and finishes by messaging back {cmd:"final"}.
  await browser.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] });
  return { ok: true };
}

async function sendToNative(imageDataUrl) {
  // Routed to SafariWebExtensionHandler in the containing app, which writes the
  // PNG to its inbox and notifies the main app. Unavailable when loaded as a
  // temporary extension (no containing app) — we surface that honestly rather
  // than trying the old data:-URL tab fallback, which Safari blocks.
  if (!imageDataUrl) throw new Error("no image");
  const resp = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, {
    type: "import",
    image: imageDataUrl,
  });
  if (resp && resp.ok) return { ok: true };
  throw new Error(resp && resp.error ? resp.error : "native returned not-ok");
}
