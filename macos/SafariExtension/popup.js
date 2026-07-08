// WorldCapture Web — popup: kick off capture, show status.
const button = document.getElementById("capture");
const status = document.getElementById("status");

button.addEventListener("click", async () => {
  button.disabled = true;
  status.textContent = "Capturing…";
  try {
    const r = await browser.runtime.sendMessage({ cmd: "start" });
    if (r && r.ok) {
      status.textContent = "Capturing… result opens in a new tab.";
    } else {
      status.textContent = "Failed: " + ((r && r.error) || "unknown");
    }
  } catch (e) {
    status.textContent = "Failed: " + String(e);
  } finally {
    button.disabled = false;
  }
});
