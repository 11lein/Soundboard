/* exported showDialog */
// Generic modal dialog, loaded as a plain <script> before renderer.js (same
// pattern as naming.js). It replaces the ~4 near-identical hand-rolled overlay
// blocks the renderer used to carry (export/import/diff/format prompts), each of
// which built an `.overlay > .dialog` node, wired button clicks and resolved a
// Promise. Centralising that here removes the duplication and keeps the markup
// (and thus the styling) consistent across every dialog.
//
// Usage:
//   const choice = await showDialog({
//     title: "Titel",                 // HTML (escape yourself if it's user data)
//     html: "<p class='muted'>…</p>",  // optional body markup
//     wide: false,                     // use the wider .dialog layout
//     buttons: [
//       { label: "Abbrechen", kind: "link", value: null },
//       { label: "OK", kind: "primary", value: (root) => readInputs(root) },
//     ],
//   });
// The returned Promise resolves to the clicked button's `value`. If `value` is a
// function it is called with the dialog root element (handy for reading checkbox
// or input state at click time). A disabled button cannot be clicked.
function showDialog({ title, html = "", wide = false, buttons = [] }) {
  return new Promise((resolve) => {
    const overlay = document.createElement("div");
    overlay.className = "overlay";
    const btnHtml = buttons
      .map((b, i) => {
        const cls = b.kind ? ` ${b.kind}` : "";
        const dis = b.disabled ? " disabled" : "";
        return `<button data-dlg="${i}" class="dlg-btn${cls}"${dis}>${b.label}</button>`;
      })
      .join("");
    overlay.innerHTML =
      `<div class="dialog${wide ? " wide" : ""}">` +
      `<h3>${title}</h3>${html}` +
      `<div class="dialog-buttons">${btnHtml}</div>` +
      `</div>`;
    document.body.appendChild(overlay);

    const done = (v) => {
      overlay.remove();
      resolve(v);
    };
    buttons.forEach((b, i) => {
      if (b.disabled) return;
      overlay.querySelector(`[data-dlg="${i}"]`).onclick = () =>
        done(typeof b.value === "function" ? b.value(overlay) : b.value);
    });
  });
}

// Expose globally for renderer.js (classic script, no module system here).
window.showDialog = showDialog;
