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

// ---------------------------------------------------------------------------
// Capture jobs — every capture is bound to ONE tab.
//
// captureVisibleTab(windowId) grabs whatever tab is *currently* active in that
// window. If the user switches tabs mid-capture, a naive grab returns the other
// tab's pixels and they get stitched into the long image. So each job records
// {tabId, windowId}; before AND after every grab we verify that tab is still the
// active one, and tab switches / closes / navigations invalidate the job. An
// invalid job never stitches and never opens a result page.
// ---------------------------------------------------------------------------
const jobs = new Map(); // tabId -> { id, tabId, windowId, invalid: string|null }

const newId = () =>
  (self.crypto && crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`);

function invalidateJob(tabId, reason) {
  const job = jobs.get(tabId);
  if (job && !job.invalid) job.invalid = reason;
}

browser.tabs.onActivated.addListener(({ tabId, windowId }) => {
  for (const job of jobs.values()) {
    if (job.windowId === windowId && job.tabId !== tabId) invalidateJob(job.tabId, "tab switched during capture");
  }
});
browser.tabs.onRemoved.addListener((tabId) => {
  invalidateJob(tabId, "tab closed during capture");
  jobs.delete(tabId);
});
browser.tabs.onUpdated.addListener((tabId, changeInfo) => {
  // Only a real navigation (status → loading). Many pages rewrite the URL while
  // scrolling (scroll-spy hashes, infinite-feed pushState) — that is not a new page.
  if (changeInfo.status === "loading") invalidateJob(tabId, "page navigated during capture");
});
if (browser.windows && browser.windows.onRemoved) {
  browser.windows.onRemoved.addListener((windowId) => {
    for (const job of jobs.values()) if (job.windowId === windowId) invalidateJob(job.tabId, "window closed during capture");
  });
}

/** Throws unless `job` is still valid and its tab is the active tab of its window. */
async function assertJobActive(job) {
  if (job.invalid) throw new Error("capture cancelled: " + job.invalid);
  let tab;
  try {
    tab = await browser.tabs.get(job.tabId);
  } catch (_) {
    invalidateJob(job.tabId, "tab closed during capture");
    throw new Error("capture cancelled: " + job.invalid);
  }
  if (!tab.active || tab.windowId !== job.windowId) {
    invalidateJob(job.tabId, "tab switched during capture");
    throw new Error("capture cancelled: " + job.invalid);
  }
}

async function grabViewport(job) {
  for (let attempt = 0; attempt < CAPTURE_MAX_ATTEMPTS; attempt++) {
    const wait = CAPTURE_MIN_INTERVAL_MS - (Date.now() - lastCaptureAt);
    if (wait > 0) await sleep(wait);
    await assertJobActive(job); // before: never capture another tab
    lastCaptureAt = Date.now();
    let dataUrl;
    try {
      dataUrl = await browser.tabs.captureVisibleTab(job.windowId, { format: "png" });
    } catch (e) {
      if (job.invalid || attempt === CAPTURE_MAX_ATTEMPTS - 1) throw e;
      await sleep(CAPTURE_MIN_INTERVAL_MS * (attempt + 1)); // linear back-off
      continue;
    }
    await assertJobActive(job); // after: a switch *during* the call voids this frame
    return dataUrl;
  }
}

// ---------------------------------------------------------------------------
// Result store — one record per result ID, kept in IndexedDB (shared with
// result.html, survives a service-worker restart). Records expire after
// RESULT_TTL_MS and at most RESULT_MAX are kept; an expired page says so
// instead of showing some other capture.
// (The same tiny helper lives in result.js; keep them in sync.)
// ---------------------------------------------------------------------------
const RESULT_DB = "worldcapture-results";
const RESULT_STORE = "results";
const RESULT_TTL_MS = 24 * 60 * 60 * 1000;
const RESULT_MAX = 8;

function openResultDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(RESULT_DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(RESULT_STORE, { keyPath: "id" });
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

function txDone(tx) {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}

async function putResult(record) {
  const db = await openResultDB();
  try {
    // Prune expired + overflow first, then add.
    const all = await new Promise((resolve, reject) => {
      const req = db.transaction(RESULT_STORE).objectStore(RESULT_STORE).getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => reject(req.error);
    });
    const now = Date.now();
    const keep = all.filter((r) => now - r.createdAt < RESULT_TTL_MS).sort((a, b) => b.createdAt - a.createdAt);
    const drop = all.filter((r) => !keep.slice(0, RESULT_MAX - 1).includes(r));
    const tx = db.transaction(RESULT_STORE, "readwrite");
    const store = tx.objectStore(RESULT_STORE);
    for (const r of drop) store.delete(r.id);
    store.put(record);
    await txDone(tx);
  } finally {
    db.close();
  }
}

// ---------------------------------------------------------------------------

browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  // From popup: begin a full-page capture of the active tab.
  if (msg.cmd === "start") {
    startCapture()
      .then((r) => sendResponse(r))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true; // keep the channel open for the async reply
  }

  // From content.js: claim the job for this tab (the ID tags every later message).
  if (msg.cmd === "begin") {
    const job = sender.tab && jobs.get(sender.tab.id);
    sendResponse(job && !job.invalid ? { jobId: job.id } : { error: "no capture job for this tab" });
    return false;
  }

  // From content.js: grab the current viewport as a PNG data URL (throttled +
  // retried, and only while the job's tab is still the active one).
  if (msg.cmd === "grab") {
    const job = sender.tab && jobs.get(sender.tab.id);
    if (!job || job.id !== msg.jobId) {
      sendResponse({ error: "capture cancelled: unknown or superseded job" });
      return false;
    }
    grabViewport(job)
      .then((dataUrl) => sendResponse({ dataUrl }))
      .catch((e) => sendResponse({ error: String(e && e.message ? e.message : e), cancelled: !!job.invalid }));
    return true;
  }

  // From content.js: the capture ended without a result (cancelled / failed).
  if (msg.cmd === "abort") {
    const job = sender.tab && jobs.get(sender.tab.id);
    if (job && job.id === msg.jobId) jobs.delete(job.tabId);
    return false;
  }

  // From content.js: the stitched full-page PNG is ready. Store it under its
  // own result ID and show it on a result page bound to that ID.
  if (msg.cmd === "final") {
    finishCapture(sender, msg)
      .then((r) => sendResponse(r))
      .catch((e) => sendResponse({ ok: false, error: String(e && e.message ? e.message : e) }));
    return true;
  }

  // From result.js: user clicked "Open in WorldCapture" — hand off to native.
  if (msg.cmd === "openInApp") {
    sendToNative(msg.image)
      .then((r) => sendResponse(r))
      .catch((e) => sendResponse({ ok: false, status: "failed", error: String(e && e.message ? e.message : e) }));
    return true;
  }

  return false;
});

async function startCapture() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab || tab.id == null) return { ok: false, error: "no active tab" };
  const job = { id: newId(), tabId: tab.id, windowId: tab.windowId, invalid: null };
  const previous = jobs.get(tab.id);
  if (previous) invalidateJob(previous.tabId, "superseded by a new capture");
  jobs.set(tab.id, job);
  // The capture script first asks for its job ID ({cmd:"begin"}), then drives
  // the scroll + per-frame grabs and finishes with {cmd:"final"}.
  await browser.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] });
  return { ok: true };
}

async function finishCapture(sender, msg) {
  const job = sender.tab && jobs.get(sender.tab.id);
  if (!job || job.id !== msg.jobId) throw new Error("capture cancelled: unknown or superseded job");
  jobs.delete(job.tabId);
  if (job.invalid) throw new Error("capture cancelled: " + job.invalid);

  // Store raw bytes (ArrayBuffer) rather than a Blob: Safari has a history of
  // IndexedDB Blob quirks; ArrayBuffer round-trips everywhere.
  const blob = await (await fetch(msg.image)).blob();
  const id = newId();
  await putResult({
    id,
    createdAt: Date.now(),
    bytes: await blob.arrayBuffer(),
    type: blob.type || "image/png",
    cssWidth: msg.cssWidth,
    scale: msg.scale,
    gaps: msg.gaps || [],
    truncated: !!msg.truncated,
  });
  await browser.tabs.create({ url: browser.runtime.getURL("result.html") + "?id=" + encodeURIComponent(id), active: true });
  return { ok: true, id };
}

async function sendToNative(imageDataUrl) {
  // Routed to SafariWebExtensionHandler in the containing app, which writes the
  // PNG to its inbox, notifies the main app, and reports whether the editor
  // actually took it ("opened") or it is waiting in the inbox ("queued").
  // Unavailable when loaded as a temporary extension (no containing app).
  if (!imageDataUrl) throw new Error("no image");
  const resp = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, {
    type: "import",
    image: imageDataUrl,
  });
  if (resp && resp.ok) return { ok: true, status: resp.status || "queued" };
  throw new Error(resp && resp.error ? resp.error : "native returned not-ok");
}
