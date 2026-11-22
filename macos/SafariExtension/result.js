// WorldCapture Web — result page. Displays one stitched full-page PNG in the
// browser (standalone, GoFullPage-style), with Download / Copy / OCR / hand-off
// to the native app.
//
// Each page is bound to ONE result by the `?id=` in its URL; the image lives in
// IndexedDB under that ID (written by background.js). Reloading or reopening an
// old page always shows its own capture — or says it has expired — never the
// latest one.

// --- result store (same helper as background.js; keep them in sync) ---------
const RESULT_DB = "worldcapture-results";
const RESULT_STORE = "results";
const RESULT_TTL_MS = 24 * 60 * 60 * 1000;

function openResultDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(RESULT_DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(RESULT_STORE, { keyPath: "id" });
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function getResult(id) {
  const db = await openResultDB();
  try {
    return await new Promise((resolve, reject) => {
      const req = db.transaction(RESULT_STORE).objectStore(RESULT_STORE).get(id);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => reject(req.error);
    });
  } finally {
    db.close();
  }
}

const blobToDataURL = (blob) =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
// -----------------------------------------------------------------------------

(async () => {
  const img = document.getElementById("shot");
  const status = document.getElementById("status");
  const dims = document.getElementById("dims");
  const warn = document.getElementById("warn");
  const copyBtn = document.getElementById("copy");
  const downloadBtn = document.getElementById("download");
  const openBtn = document.getElementById("open");
  const stage = document.querySelector(".stage");

  const setStatus = (t) => (status.textContent = t || "");
  const showEmpty = (text) => {
    stage.innerHTML = "";
    const div = document.createElement("div");
    div.className = "empty";
    div.textContent = text;
    stage.appendChild(div);
  };

  const id = new URLSearchParams(location.search).get("id");
  if (!id) {
    showEmpty("No capture to show. Run a capture from the toolbar button.");
    return;
  }

  let record = null;
  try {
    record = await getResult(id);
  } catch (e) {
    setStatus("Load failed");
  }
  if (!record || !(record.bytes || record.blob) || Date.now() - record.createdAt >= RESULT_TTL_MS) {
    showEmpty("这张截图已过期或已被清理，请重新截取。 / This capture has expired. Please capture again.");
    return;
  }

  const blob = record.bytes ? new Blob([record.bytes], { type: record.type || "image/png" }) : record.blob;
  const scale = record.scale;
  const objectURL = URL.createObjectURL(blob);

  const notes = [];
  if (record.gaps && record.gaps.length) {
    notes.push(`页面滚动时有 ${record.gaps.length} 处未能覆盖（滚动吸附），长图在这些位置不连续。`);
  }
  if (record.truncated) notes.push("长图未拍到页面底部（达到高度上限或页面无法继续滚动）。");
  if (notes.length) {
    warn.textContent = "⚠️ " + notes.join(" ");
    warn.hidden = false;
  }

  // Zoom control. On a Retina display the capture is 2× device pixels, so "50%"
  // shows it at true native density (crispest); "适应宽度" fits the window.
  const applyZoom = (mode) => {
    if (mode === "fit") {
      img.style.width = "";
      img.style.maxWidth = "100%";
    } else {
      img.style.maxWidth = "none";
      img.style.width = Math.round(img.naturalWidth * parseFloat(mode)) + "px";
    }
    document.querySelectorAll("#zoom button").forEach((b) => {
      b.classList.toggle("on", b.dataset.zoom === mode);
    });
  };
  document.querySelectorAll("#zoom button").forEach((b) => {
    b.addEventListener("click", () => applyZoom(b.dataset.zoom));
  });

  img.src = objectURL;
  img.onload = () => {
    const badge = scale ? ` · ${scale}×` : "";
    dims.textContent = `${img.naturalWidth} × ${img.naturalHeight}${badge}`;
    copyBtn.disabled = downloadBtn.disabled = openBtn.disabled = false;
    if (window.Tesseract) document.getElementById("ocr").disabled = false;
  };

  downloadBtn.addEventListener("click", () => {
    const a = document.createElement("a");
    a.href = objectURL;
    a.download = `worldcapture-fullpage.png`;
    document.body.appendChild(a);
    a.click();
    a.remove();
  });

  copyBtn.addEventListener("click", async () => {
    setStatus("Copying…");
    try {
      await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
      setStatus("Copied");
    } catch (e) {
      setStatus("Copy unavailable");
    }
  });

  // In-browser OCR (standalone, no app needed) via bundled Tesseract.js.
  //
  // Two packaging pitfalls, both fixed here:
  //  · The library defaults to a blob: Worker (importScripts from a blob URL),
  //    which the manifest CSP `worker-src 'self'` forbids → workerBlobURL:false
  //    loads worker.min.js straight from the extension package.
  //  · Given a *directory* corePath, the worker picks a core by OCR mode: LSTM
  //    mode (OEM 1) asks for tesseract-core-simd-lstm.wasm.js, which we do not
  //    ship. Point corePath at the exact core file we bundle; it contains the
  //    full engine (LSTM included) and loads its .wasm from the same folder.
  const ocrBtn = document.getElementById("ocr");
  const ocrLang = document.getElementById("ocrLang");
  const ocrPanel = document.getElementById("ocrPanel");
  const ocrText = document.getElementById("ocrText");
  const ocrStatus = document.getElementById("ocrStatus");
  const ocrCopy = document.getElementById("ocrCopy");
  let ocrBusy = false;

  ocrBtn.addEventListener("click", async () => {
    if (ocrBusy || !window.Tesseract) return;
    ocrBusy = true;
    ocrBtn.disabled = true;
    ocrPanel.hidden = false;
    ocrText.value = "";
    ocrStatus.textContent = "初始化…";
    const base = browser.runtime.getURL("vendor/tesseract/");
    let worker;
    try {
      worker = await window.Tesseract.createWorker(ocrLang.value, 1, {
        workerPath: base + "worker.min.js",
        workerBlobURL: false,
        corePath: base + "tesseract-core-simd.wasm.js",
        langPath: base + "lang",
        gzip: true,
        logger: (m) => {
          if (m.status === "recognizing text") {
            ocrStatus.textContent = `识别中… ${Math.round((m.progress || 0) * 100)}%`;
          } else if (m.status) {
            ocrStatus.textContent = m.status;
          }
        },
      });
      const { data } = await worker.recognize(blob);
      ocrText.value = (data.text || "").trim();
      ocrStatus.textContent = ocrText.value ? "完成" : "未识别到文字";
    } catch (e) {
      ocrStatus.textContent = "识别失败：" + String(e && e.message ? e.message : e) + "（可再点一次重试）";
    } finally {
      if (worker) { try { await worker.terminate(); } catch (_) {} }
      ocrBusy = false;
      ocrBtn.disabled = false;
    }
  });

  ocrCopy.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(ocrText.value);
      ocrStatus.textContent = "已复制";
    } catch (e) {
      ocrStatus.textContent = "复制失败";
    }
  });

  openBtn.addEventListener("click", async () => {
    openBtn.disabled = true;
    setStatus("Sending…");
    try {
      const image = await blobToDataURL(blob);
      const r = await browser.runtime.sendMessage({ cmd: "openInApp", image });
      if (r && r.ok && r.status === "opened") setStatus("已在 WorldCapture 中打开 / Opened in WorldCapture");
      else if (r && r.ok) setStatus("已交给 WorldCapture，打开 App（或录屏结束）后会自动载入 / Queued — opens when WorldCapture is ready");
      else setStatus("App unavailable" + (r && r.error ? `: ${r.error}` : ""));
    } catch (e) {
      setStatus("App unavailable");
    } finally {
      openBtn.disabled = false;
    }
  });
})();
