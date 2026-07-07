// WorldCapture Web — background service worker.
// Orchestrates full-page capture: injects content.js, serves per-frame
// captureVisibleTab grabs, and hands the stitched PNG to the native app.

const NATIVE_APP_ID = "io.worldcapture.app.Extension";

async function activeTab() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  return tab;
}

browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  // From popup: begin a full-page capture of the active tab.
  if (msg.cmd === "start") {
    startCapture()
      .then((r) => sendResponse(r))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true; // keep the channel open for the async reply
  }

  // From content.js: grab the current viewport as a PNG data URL.
  if (msg.cmd === "grab") {
    const windowId = sender.tab ? sender.tab.windowId : undefined;
    browser.tabs
      .captureVisibleTab(windowId, { format: "png" })
      .then((dataUrl) => sendResponse({ dataUrl }))
      .catch((e) => sendResponse({ error: String(e) }));
    return true;
  }

  // From content.js: the stitched full-page PNG is ready — hand off to native.
  if (msg.cmd === "final") {
    sendToNative(msg.image)
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
  // In Safari this is routed to SafariWebExtensionHandler in the containing app.
  const resp = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, {
    type: "import",
    image: imageDataUrl,
  });
  return resp || { ok: true };
}
