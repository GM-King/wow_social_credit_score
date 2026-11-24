const updated = document.getElementById("release-updated");

if (updated && typeof Intl.RelativeTimeFormat === "function") {
  const releasedAt = Date.parse(updated.dateTime);
  if (Number.isFinite(releasedAt)) {
    const format = new Intl.RelativeTimeFormat("en", { numeric: "always" });
    const units = [["year", 31536000], ["month", 2592000], ["day", 86400], ["hour", 3600], ["minute", 60]];
    updated.title = updated.textContent;

    const render = () => {
      const seconds = Math.max(0, (Date.now() - releasedAt) / 1000);
      const unit = units.find(([, size]) => seconds >= size);
      updated.textContent = unit ? format.format(-Math.floor(seconds / unit[1]), unit[0]) : "just now";
    };

    render();
    window.setInterval(render, 30000);
  }
}

