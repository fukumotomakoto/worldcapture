// WorldCapture Web — result page. Displays the stitched full-page PNG in the
// browser (standalone, GoFullPage-style), with Download / Copy / hand-off to
// the native app. The image is held in the background worker; we request it.

(async () => {
  const img = document.getElementById("shot");
  const status = document.getElementById("status");
  const dims = document.getElementById("dims");
  const copyBtn = document.getElementById("copy");
  const downloadBtn = document.getElementById("download");
  const openBtn = document.getElementById("open");
  const stage = document.querySelector(".stage");

  const setStatus = (t) => (status.textContent = t || "");

  let dataUrl = null;
  try {
    const r = await browser.runtime.sendMessage({ cmd: "getResult" });
    dataUrl = r && r.image;
  } catch (e) {
    setStatus("Load failed");
  }

  if (!dataUrl) {
    stage.innerHTML = '<div class="empty">No capture to show. Run a capture from the toolbar button.</div>';
    return;
  }

  img.src = dataUrl;
  img.onload = () => {
    dims.textContent = `${img.naturalWidth} × ${img.naturalHeight}`;
    copyBtn.disabled = downloadBtn.disabled = openBtn.disabled = false;
  };

  downloadBtn.addEventListener("click", () => {
    const a = document.createElement("a");
    a.href = dataUrl;
    a.download = `worldcapture-fullpage.png`;
    document.body.appendChild(a);
    a.click();
    a.remove();
  });

  copyBtn.addEventListener("click", async () => {
    setStatus("Copying…");
    try {
      const blob = await (await fetch(dataUrl)).blob();
      await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
      setStatus("Copied");
    } catch (e) {
      setStatus("Copy unavailable");
    }
  });

  openBtn.addEventListener("click", async () => {
    openBtn.disabled = true;
    setStatus("Opening…");
    try {
      const r = await browser.runtime.sendMessage({ cmd: "openInApp", image: dataUrl });
      setStatus(r && r.ok ? "Opened in WorldCapture" : "App unavailable");
    } catch (e) {
      setStatus("App unavailable");
    } finally {
      openBtn.disabled = false;
    }
  });
})();
