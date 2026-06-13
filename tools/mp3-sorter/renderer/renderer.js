/* global naming, api */
const { BANK_SIZE, NUM_BANKS, TOTAL_SLOTS, finalName, bankOfSlot } = naming;

const state = {
  folder: null,
  order: [], // filenames in slot order (index 0 = slot 1)
  dirty: false,
};

// Session-remembered move choice: null | "swap" | "shift"
let rememberedMove = null;

// Single audio player. Only the current track keeps its position; switching to
// another track stops the old one and resets it to 0s.
const player = { audio: new Audio(), index: null, playing: false };
player.audio.addEventListener("ended", () => {
  player.audio.currentTime = 0;
  player.playing = false;
  updatePlayButtons();
});

function stopPlayer() {
  player.audio.pause();
  player.audio.currentTime = 0;
  player.index = null;
  player.playing = false;
}

async function playToggle(orderIndex) {
  if (player.index === orderIndex) {
    // Same track: toggle play/pause, keeping its current position.
    if (player.playing) {
      player.audio.pause();
      player.playing = false;
    } else {
      await player.audio.play();
      player.playing = true;
    }
  } else {
    // Different track: stop & reset the previous one, start this from 0s.
    player.audio.pause();
    player.audio.currentTime = 0;
    const url = await api.fileUrl(state.folder, state.order[orderIndex]);
    player.audio.src = url;
    player.audio.currentTime = 0;
    player.index = orderIndex;
    await player.audio.play();
    player.playing = true;
  }
  updatePlayButtons();
}

// Update only the button glyphs (no full re-render, so playback isn't disturbed).
function updatePlayButtons() {
  document.querySelectorAll(".play-btn").forEach((btn) => {
    const idx = Number(btn.dataset.index);
    const active = idx === player.index && player.playing;
    btn.textContent = active ? "⏸" : "▶";
    btn.classList.toggle("playing", active);
  });
}

const el = {
  list: document.getElementById("list"),
  emptyHint: document.getElementById("empty-hint"),
  folderPath: document.getElementById("folder-path"),
  status: document.getElementById("status"),
  openBtn: document.getElementById("open-btn"),
  previewBtn: document.getElementById("preview-btn"),
  pdfBtn: document.getElementById("pdf-btn"),
  saveDraftBtn: document.getElementById("save-draft-btn"),
  commitBtn: document.getElementById("commit-btn"),
  dropZone: document.getElementById("drop-zone"),
  moveDialog: document.getElementById("move-dialog"),
  moveText: document.getElementById("move-text"),
  moveSwap: document.getElementById("move-swap"),
  moveShift: document.getElementById("move-shift"),
  moveRemember: document.getElementById("move-remember"),
  moveCancel: document.getElementById("move-cancel"),
};

// ---------- Rendering ----------
// Light background colour for a cell at visual row/col (physical key coding).
function cellBg(vr, col) {
  const name = api.colors.rows[vr][col];
  return api.colors.palette[name].bg;
}

// Render one bank as a 5x5 grid laid out like the physical box:
// bottom-left = key A (first slot), top-right = Y (mode key, blocked).
function makeBankGrid(bankIndex) {
  const bankNo = bankIndex + 1;
  const start = bankIndex * BANK_SIZE + 1; // 1-based slot of key A in this bank

  const wrap = document.createElement("div");
  wrap.className = "bank";
  const header = document.createElement("div");
  header.className = "bank-header";
  header.innerHTML = `Bank ${bankNo} <span class="keys">Slots ${start}–${
    start + BANK_SIZE - 1
  }</span>`;
  wrap.appendChild(header);

  const grid = document.createElement("div");
  grid.className = "grid";
  // visualRow 0 = top, 4 = bottom. Position alone identifies the key (no letters).
  for (let vr = 0; vr < 5; vr++) {
    for (let col = 0; col < 5; col++) {
      const posIndex = (4 - vr) * 5 + col; // 0..24 in physical key order
      const cell = document.createElement("div");
      cell.style.background = cellBg(vr, col);

      if (posIndex === 24) {
        // Top-right key: mode button, not assignable
        cell.className = "cell blocked";
        cell.innerHTML = `<div class="cell-note">Mode</div>`;
        grid.appendChild(cell);
        continue;
      }

      const slot = start + posIndex;
      const orderIndex = slot - 1;
      const fname = state.order[orderIndex];

      cell.className = "cell";
      cell.dataset.index = String(orderIndex);
      const active = orderIndex === player.index && player.playing;
      const playBtn = fname
        ? `<button class="play-btn${
            active ? " playing" : ""
          }" data-index="${orderIndex}" draggable="false">${
            active ? "⏸" : "▶"
          }</button>`
        : "";
      const top = `<div class="cell-top">${playBtn}<span class="slot">${naming.pad4(
        naming.prefixForSlot(slot)
      )}</span></div>`;

      if (fname) {
        if (finalName(slot, fname) !== fname) cell.classList.add("renamed");
        cell.draggable = true;
        cell.innerHTML =
          top +
          `<div class="fname" title="${escapeHtml(fname)} → ${escapeHtml(
            finalName(slot, fname)
          )}">${escapeHtml(fname)}</div>`;
        const btn = cell.querySelector(".play-btn");
        btn.addEventListener("click", (e) => {
          e.stopPropagation();
          playToggle(orderIndex);
        });
      } else {
        cell.classList.add("empty");
        cell.innerHTML = top + `<div class="fname muted">—</div>`;
      }
      attachCellDnd(cell);
      grid.appendChild(cell);
    }
  }
  wrap.appendChild(grid);
  return wrap;
}

function render() {
  el.list.innerHTML = "";
  el.emptyHint.classList.toggle("hidden", state.order.length > 0);

  if (state.order.length > 0) {
    for (let b = 0; b < NUM_BANKS; b++) el.list.appendChild(makeBankGrid(b));

    // Anything beyond the 144 slots gets a flagged overflow list.
    if (state.order.length > TOTAL_SLOTS) {
      const ov = document.createElement("div");
      ov.className = "bank";
      ov.innerHTML = `<div class="bank-header bank-overflow">⚠️ Überlauf – ${
        state.order.length - TOTAL_SLOTS
      } Datei(en) über Bank ${NUM_BANKS} (Slot &gt; ${TOTAL_SLOTS})</div>`;
      for (let i = TOTAL_SLOTS; i < state.order.length; i++) {
        const row = document.createElement("div");
        row.className = "row renamed";
        row.dataset.index = String(i);
        row.draggable = true;
        row.innerHTML = `<span class="slot">${naming.pad4(
          naming.prefixForSlot(i + 1)
        )}</span><span class="fname">${escapeHtml(state.order[i])}</span>`;
        attachCellDnd(row);
        ov.appendChild(row);
      }
      el.list.appendChild(ov);
    }
  }

  const renames = state.order.filter(
    (f, i) => finalName(i + 1, f) !== f
  ).length;
  el.status.textContent = state.order.length
    ? `${state.order.length} Dateien · ${renames} werden umbenannt${
        state.dirty ? " · ungespeichert" : ""
      }`
    : "";
  el.saveDraftBtn.disabled = !state.folder || state.order.length === 0;
  el.commitBtn.disabled = !state.folder || renames === 0;
  el.pdfBtn.disabled = state.order.length === 0;
  el.previewBtn.disabled = state.order.length === 0;
}

// Display name for the printout: prefix and .mp3 extension stripped.
function displayName(fname) {
  return naming.stripPrefix(fname).replace(/\.mp3$/i, "");
}

// Build a self-contained A4-landscape HTML page: a 5x5 key grid where every
// cell lists all 6 banks (one line each), names truncated, no wrapping.
function buildPrintHtml() {
  let cells = "";
  for (let vr = 0; vr < 5; vr++) {
    for (let col = 0; col < 5; col++) {
      const posIndex = (4 - vr) * 5 + col; // physical key order, A bottom-left
      const bg = cellBg(vr, col);
      if (posIndex === 24) {
        cells += `<div class="pcell blocked" style="background:${bg}"><div class="pmode">Mode</div></div>`;
        continue;
      }
      let lines = "";
      for (let b = 0; b < NUM_BANKS; b++) {
        const fname = state.order[b * BANK_SIZE + posIndex];
        const text = fname ? escapeHtml(displayName(fname)) : "";
        lines += `<div class="pline"><span class="pb">${
          b + 1
        }</span><span class="pt">${text}</span></div>`;
      }
      cells += `<div class="pcell" style="background:${bg}">${lines}</div>`;
    }
  }
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
    @page { size: A4 landscape; margin: 8mm; }
    * { box-sizing: border-box; }
    body { font-family: Arial, Helvetica, sans-serif; margin: 0; color: #000; }
    .pgrid { display: grid; grid-template-columns: repeat(5, 1fr); grid-auto-rows: min-content; gap: 2mm; }
    .pcell { border: 0.5pt solid #999; border-radius: 1.5mm; padding: 1.2mm; overflow: hidden; }
    .pline { display: flex; align-items: center; gap: 1.5mm; font-size: 7.5pt; line-height: 1.45; height: 1.45em; }
    .pb { color: #fff; background: #555; border-radius: 1mm; padding: 0 1mm; font-size: 6.5pt; flex: none; }
    .pt { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .pcell.blocked { display: flex; align-items: center; justify-content: center; }
    .pmode { font-size: 7pt; color: #666; text-transform: uppercase; letter-spacing: 0.5pt; }
  </style></head><body>
    <div class="pgrid">${cells}</div>
  </body></html>`;
}

function escapeHtml(s) {
  return s.replace(
    /[&<>"]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

function markDirty() {
  state.dirty = true;
  render();
}

// ---------- Drag & drop reordering ----------
let dragFrom = null;

function attachCellDnd(cell) {
  cell.addEventListener("dragstart", (e) => {
    if (!cell.draggable || (e.target.closest && e.target.closest(".play-btn"))) {
      e.preventDefault();
      return;
    }
    dragFrom = Number(cell.dataset.index);
    cell.classList.add("dragging");
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", "cell"); // mark as internal reorder
  });
  cell.addEventListener("dragend", () => {
    cell.classList.remove("dragging");
    document
      .querySelectorAll(".drop-target")
      .forEach((r) => r.classList.remove("drop-target"));
    dragFrom = null;
  });
  cell.addEventListener("dragover", (e) => {
    if (dragFrom === null) return; // external file drag handled elsewhere
    e.preventDefault();
    e.stopPropagation();
    cell.classList.add("drop-target");
  });
  cell.addEventListener("dragleave", () => cell.classList.remove("drop-target"));
  cell.addEventListener("drop", async (e) => {
    if (dragFrom === null) return;
    e.preventDefault();
    e.stopPropagation();
    cell.classList.remove("drop-target");
    const to = Number(cell.dataset.index);
    if (to === dragFrom) return;
    if (to >= state.order.length) {
      // Dropped on an empty trailing slot -> just move the file to the end.
      const [item] = state.order.splice(dragFrom, 1);
      state.order.push(item);
      markDirty();
      return;
    }
    await applyMove(dragFrom, to);
  });
}

async function applyMove(from, to) {
  const choice = rememberedMove || (await askMove(from, to));
  if (!choice) return; // cancelled
  if (choice === "swap") {
    const tmp = state.order[from];
    state.order[from] = state.order[to];
    state.order[to] = tmp;
  } else {
    // shift: remove from old position, insert at target (push following down)
    const [item] = state.order.splice(from, 1);
    state.order.splice(to, 0, item);
  }
  markDirty();
}

function askMove(from, to) {
  return new Promise((resolve) => {
    el.moveText.textContent = `„${state.order[from]}" auf Slot ${
      to + 1
    } verschieben:`;
    el.moveRemember.checked = false;
    el.moveDialog.classList.remove("hidden");

    const finish = (val) => {
      el.moveDialog.classList.add("hidden");
      el.moveSwap.onclick = el.moveShift.onclick = el.moveCancel.onclick = null;
      if (val && el.moveRemember.checked) rememberedMove = val;
      resolve(val);
    };
    el.moveSwap.onclick = () => finish("swap");
    el.moveShift.onclick = () => finish("shift");
    el.moveCancel.onclick = () => finish(null);
  });
}

// ---------- Loading ----------
async function loadFolder(folder) {
  stopPlayer();
  state.folder = folder;
  el.folderPath.textContent = folder;
  const files = await api.listMp3(folder);
  const draft = await api.loadDraft(folder);

  if (draft && Array.isArray(draft.order)) {
    // Keep the draft order, drop missing files, append new ones at the end.
    const present = new Set(files);
    const kept = draft.order.filter((f) => present.has(f));
    const known = new Set(kept);
    const added = files.filter((f) => !known.has(f));
    state.order = kept.concat(naming.buildInitialOrder(added));
  } else {
    state.order = naming.buildInitialOrder(files);
  }
  state.dirty = false;
  render();
}

// ---------- Toolbar ----------
el.openBtn.addEventListener("click", async () => {
  const folder = await api.pickFolder();
  if (folder) await loadFolder(folder);
});

el.previewBtn.addEventListener("click", async () => {
  if (!state.order.length) return;
  el.status.textContent = "Erzeuge Vorschau…";
  const res = await api.previewPdf(buildPrintHtml());
  el.status.textContent = res && res.error ? "Vorschau-Fehler: " + res.error : "";
  if (res && res.error) alert("Vorschau-Fehler: " + res.error);
});

el.pdfBtn.addEventListener("click", async () => {
  if (!state.order.length) return;
  el.status.textContent = "Erzeuge PDF…";
  const res = await api.exportPdf(buildPrintHtml());
  if (res && res.ok) el.status.textContent = "PDF gespeichert: " + res.path;
  else if (res && res.error) alert("PDF-Fehler: " + res.error);
  else el.status.textContent = "";
});

el.saveDraftBtn.addEventListener("click", async () => {
  if (!state.folder) return;
  await api.saveDraft(state.folder, { order: state.order });
  state.dirty = false;
  el.status.textContent = "Zwischengespeichert ✔";
  setTimeout(render, 1200);
});

el.commitBtn.addEventListener("click", async () => {
  if (!state.folder) return;
  const renames = state.order.filter((f, i) => finalName(i + 1, f) !== f).length;
  if (
    !confirm(
      `${renames} Datei(en) werden jetzt auf der Festplatte umbenannt. Fortfahren?`
    )
  )
    return;
  stopPlayer(); // release file handles before renaming on disk
  const res = await api.commitRename(state.folder, state.order);
  if (!res.ok) {
    alert("Fehler beim Umbenennen: " + res.error);
    return;
  }
  state.order = res.order;
  state.dirty = false;
  render();
  el.status.textContent = `✅ ${res.renamed} Dateien umbenannt`;
});

// ---------- External drag & drop (load folder / add files) ----------
el.dropZone.addEventListener("dragover", (e) => {
  if (dragFrom !== null) return; // internal reorder
  e.preventDefault();
  el.dropZone.classList.add("dragover");
});
el.dropZone.addEventListener("dragleave", (e) => {
  if (e.target === el.dropZone) el.dropZone.classList.remove("dragover");
});
el.dropZone.addEventListener("drop", async (e) => {
  if (dragFrom !== null) return; // handled by row drop
  e.preventDefault();
  el.dropZone.classList.remove("dragover");

  const paths = [...e.dataTransfer.files].map((f) => api.pathForFile(f)).filter(Boolean);
  if (!paths.length) return;
  const info = await api.inspectPaths(paths);

  const dir = info.find((i) => i.isDir);
  if (dir) {
    await loadFolder(dir.path);
    return;
  }
  const mp3s = info.filter((i) => i.name.toLowerCase().endsWith(".mp3"));
  if (!mp3s.length) return;

  if (state.folder) {
    const n = await api.copyInto(state.folder, mp3s.map((i) => i.path));
    el.status.textContent = `${n} Datei(en) hinzugefügt`;
    await reloadKeepingOrder();
  } else {
    // No folder yet: adopt the parent directory of the dropped files.
    await loadFolder(mp3s[0].dir);
  }
});

// Reload file list but keep the current manual order (new files appended).
async function reloadKeepingOrder() {
  const files = await api.listMp3(state.folder);
  const present = new Set(files);
  const kept = state.order.filter((f) => present.has(f));
  const known = new Set(kept);
  const added = files.filter((f) => !known.has(f));
  state.order = kept.concat(naming.buildInitialOrder(added));
  markDirty();
}
