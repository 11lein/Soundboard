/* global naming, api */
const { BANK_SIZE, NUM_BANKS, TOTAL_SLOTS, prefixForSlot, pad4 } = naming;

// Model: 144 slots (gaps allowed) + a parked list of unprefixed files.
// entry = { orig: on-disk filename, base: descriptive name (no slot prefix, .mp3 kept) }
const state = {
  folder: null,
  slots: new Array(TOTAL_SLOTS).fill(null),
  parked: [],
  dirty: false,
};

const el = {
  gridWrap: document.getElementById("grid-wrap"),
  parkingWrap: document.getElementById("parking-wrap"),
  emptyHint: document.getElementById("empty-hint"),
  folderPath: document.getElementById("folder-path"),
  status: document.getElementById("status"),
  openBtn: document.getElementById("open-btn"),
  renameBtn: document.getElementById("rename-btn"),
  sdBtn: document.getElementById("sd-btn"),
  previewBtn: document.getElementById("preview-btn"),
  pdfBtn: document.getElementById("pdf-btn"),
  saveDraftBtn: document.getElementById("save-draft-btn"),
  commitBtn: document.getElementById("commit-btn"),
  dropZone: document.getElementById("drop-zone"),
  // renamer
  rnDialog: document.getElementById("rename-dialog"),
  rnSearch: document.getElementById("rn-search"),
  rnReplace: document.getElementById("rn-replace"),
  rnRegex: document.getElementById("rn-regex"),
  rnCase: document.getElementById("rn-case"),
  rnError: document.getElementById("rn-error"),
  rnCount: document.getElementById("rn-count"),
  rnPreview: document.getElementById("rn-preview"),
  rnApply: document.getElementById("rn-apply"),
  rnCancel: document.getElementById("rn-cancel"),
};

function displayName(base) {
  return base.replace(/\.mp3$/i, "");
}
function countFiles() {
  return state.slots.filter(Boolean).length + state.parked.length;
}
function escapeHtml(s) {
  return s.replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}
function cellBg(vr, col) {
  const name = api.colors.rows[vr][col];
  return api.colors.palette[name].bg;
}

// ---------- Audio player (single; only current track keeps position) ----------
const player = { audio: new Audio(), orig: null, playing: false };
player.audio.addEventListener("ended", () => {
  player.audio.currentTime = 0;
  player.playing = false;
  updatePlayButtons();
});
function stopPlayer() {
  player.audio.pause();
  player.audio.currentTime = 0;
  player.orig = null;
  player.playing = false;
}
async function playToggle(orig) {
  if (player.orig === orig) {
    if (player.playing) {
      player.audio.pause();
      player.playing = false;
    } else {
      await player.audio.play();
      player.playing = true;
    }
  } else {
    player.audio.pause();
    player.audio.currentTime = 0;
    player.audio.src = await api.fileUrl(state.folder, orig);
    player.audio.currentTime = 0;
    player.orig = orig;
    await player.audio.play();
    player.playing = true;
  }
  updatePlayButtons();
}
function updatePlayButtons() {
  document.querySelectorAll(".play-btn").forEach((btn) => {
    const active = btn.dataset.orig === player.orig && player.playing;
    btn.textContent = active ? "⏸" : "▶";
    btn.classList.toggle("playing", active);
  });
}

// ---------- Drag & drop ----------
let drag = null; // { kind: 'slot'|'parked', index }

function makeLine(entry, target) {
  // target = { kind:'slot', slot } | { kind:'parked', index }
  const line = document.createElement("div");
  line.className = "line" + (entry ? "" : " line-empty");
  if (target.kind === "slot") line.dataset.slot = String(target.slot);
  else line.dataset.parked = String(target.index);

  if (entry) {
    line.draggable = true;
    line.innerHTML =
      `<button class="play-btn" data-orig="${escapeHtml(entry.orig)}" draggable="false">▶</button>` +
      `<span class="lname" title="${escapeHtml(entry.base)}">${escapeHtml(displayName(entry.base))}</span>`;
    line.querySelector(".play-btn").addEventListener("click", (e) => {
      e.stopPropagation();
      playToggle(entry.orig);
    });
    line.addEventListener("dragstart", (e) => {
      if (e.target.closest && e.target.closest(".play-btn")) {
        e.preventDefault();
        return;
      }
      drag =
        target.kind === "slot"
          ? { kind: "slot", index: target.slot }
          : { kind: "parked", index: target.index };
      line.classList.add("dragging");
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", "line");
    });
    line.addEventListener("dragend", () => {
      line.classList.remove("dragging");
      document.querySelectorAll(".drop-target").forEach((r) => r.classList.remove("drop-target"));
      drag = null;
    });
  }

  // every slot line is a drop target; parked lines are not (parking auto-sorts)
  if (target.kind === "slot") {
    line.addEventListener("dragover", (e) => {
      if (!drag) return;
      e.preventDefault();
      e.stopPropagation();
      line.classList.add("drop-target");
    });
    line.addEventListener("dragleave", () => line.classList.remove("drop-target"));
    line.addEventListener("drop", (e) => {
      if (!drag) return;
      e.preventDefault();
      e.stopPropagation();
      line.classList.remove("drop-target");
      dropOnSlot(target.slot);
    });
  }
  return line;
}

function dropOnSlot(slot) {
  if (drag.kind === "slot") {
    if (drag.index === slot) return;
    const a = state.slots[drag.index];
    state.slots[drag.index] = state.slots[slot];
    state.slots[slot] = a;
  } else {
    // parked -> slot (swap displaced file back to parking)
    const entry = state.parked.splice(drag.index, 1)[0];
    const displaced = state.slots[slot];
    state.slots[slot] = entry;
    if (displaced) state.parked.push(displaced);
    sortParked();
  }
  markDirty();
}

function dropOnParking() {
  if (!drag || drag.kind !== "slot") return;
  const entry = state.slots[drag.index];
  if (!entry) return;
  state.slots[drag.index] = null; // prefix removed (no slot anymore)
  state.parked.push(entry);
  sortParked();
  markDirty();
}

function sortParked() {
  state.parked.sort((a, b) =>
    a.base.localeCompare(b.base, undefined, { sensitivity: "base" })
  );
}

// ---------- Rendering ----------
function render() {
  const has = countFiles() > 0;
  el.emptyHint.classList.toggle("hidden", has);

  // --- main grid: 5x5 keys, each with 6 bank lines (PDF-style) ---
  el.gridWrap.innerHTML = "";
  if (has) {
    const grid = document.createElement("div");
    grid.className = "keygrid";
    for (let vr = 0; vr < 5; vr++) {
      for (let col = 0; col < 5; col++) {
        const posIndex = (4 - vr) * 5 + col; // box layout
        const cell = document.createElement("div");
        cell.className = "cell";
        cell.style.background = cellBg(vr, col);
        if (posIndex === 24) {
          cell.classList.add("blocked");
          cell.innerHTML = `<div class="cell-note">MODE</div>`;
          grid.appendChild(cell);
          continue;
        }
        for (let b = 0; b < NUM_BANKS; b++) {
          const slot = b * BANK_SIZE + posIndex; // 0-based slot index
          cell.appendChild(makeLine(state.slots[slot], { kind: "slot", slot }));
        }
        grid.appendChild(cell);
      }
    }
    el.gridWrap.appendChild(grid);
  }

  // --- parking area: rows of 5 boxes x 6 lines (alphabetical) ---
  el.parkingWrap.innerHTML = "";
  if (state.parked.length || has) {
    const head = document.createElement("div");
    head.className = "parking-head";
    head.textContent = `Parkplätze (ohne Prefix) – ${state.parked.length}`;
    el.parkingWrap.appendChild(head);

    const boxes = document.createElement("div");
    boxes.className = "parkboxes";
    const groups = Math.max(5, Math.ceil(state.parked.length / 6));
    for (let g = 0; g < groups; g++) {
      const box = document.createElement("div");
      box.className = "cell park";
      for (let r = 0; r < 6; r++) {
        const idx = g * 6 + r;
        box.appendChild(
          idx < state.parked.length
            ? makeLine(state.parked[idx], { kind: "parked", index: idx })
            : makeLine(null, { kind: "parked", index: idx })
        );
      }
      boxes.appendChild(box);
    }
    el.parkingWrap.appendChild(boxes);

    // dropping a slot line anywhere on the parking area unassigns it
    boxes.addEventListener("dragover", (e) => {
      if (drag && drag.kind === "slot") {
        e.preventDefault();
        boxes.classList.add("drop-target");
      }
    });
    boxes.addEventListener("dragleave", () => boxes.classList.remove("drop-target"));
    boxes.addEventListener("drop", (e) => {
      if (drag && drag.kind === "slot") {
        e.preventDefault();
        boxes.classList.remove("drop-target");
        dropOnParking();
      }
    });
  }

  updatePlayButtons();
  updateToolbar();
}

function renamePlan() {
  const plan = [];
  state.slots.forEach((entry, i) => {
    if (!entry) return;
    const to = `${pad4(prefixForSlot(i + 1))}_${entry.base}`;
    if (to !== entry.orig) plan.push({ from: entry.orig, to, entry, kind: "slot" });
  });
  for (const entry of state.parked) {
    if (entry.base !== entry.orig)
      plan.push({ from: entry.orig, to: entry.base, entry, kind: "parked" });
  }
  return plan;
}

function updateToolbar() {
  const n = countFiles();
  const renames = renamePlan().length;
  el.status.textContent = n
    ? `${n} Dateien · ${state.slots.filter(Boolean).length} platziert · ${state.parked.length} geparkt${
        state.dirty ? " · ungespeichert" : ""
      }`
    : "";
  el.saveDraftBtn.disabled = !state.folder || n === 0;
  el.commitBtn.disabled = !state.folder || renames === 0;
  el.previewBtn.disabled = n === 0;
  el.pdfBtn.disabled = n === 0;
  el.renameBtn.disabled = n === 0;
  el.sdBtn.disabled = !state.folder || state.slots.filter(Boolean).length === 0;
}

function markDirty() {
  state.dirty = true;
  render();
}

// ---------- Loading ----------
function autoAssign(filename) {
  const { num } = naming.parsePrefix(filename);
  const slot = num === null ? null : naming.slotFromPrefix(num);
  const entry = { orig: filename, base: naming.stripPrefix(filename) };
  if (slot !== null && state.slots[slot - 1] === null) state.slots[slot - 1] = entry;
  else state.parked.push(entry);
}

function buildModel(files, draft) {
  state.slots = new Array(TOTAL_SLOTS).fill(null);
  state.parked = [];
  const present = new Set(files);
  const used = new Set();

  if (draft && Array.isArray(draft.slots)) {
    draft.slots.forEach((e, i) => {
      if (e && present.has(e.orig)) {
        state.slots[i] = { orig: e.orig, base: e.base };
        used.add(e.orig);
      }
    });
    for (const e of draft.parked || []) {
      if (e && present.has(e.orig)) {
        state.parked.push({ orig: e.orig, base: e.base });
        used.add(e.orig);
      }
    }
    for (const f of files) if (!used.has(f)) autoAssign(f);
  } else {
    for (const f of files) autoAssign(f);
  }
  sortParked();
}

async function loadFolder(folder) {
  stopPlayer();
  state.folder = folder;
  el.folderPath.textContent = folder;
  const files = await api.listMp3(folder);
  const draft = await api.loadDraft(folder);
  buildModel(files, draft);
  state.dirty = false;
  render();
}

async function reloadKeepingModel() {
  const files = await api.listMp3(state.folder);
  buildModel(files, draftFromState()); // keep current arrangement, add new files
  markDirty();
}
function draftFromState() {
  return { slots: state.slots, parked: state.parked };
}

// ---------- Toolbar actions ----------
el.openBtn.addEventListener("click", async () => {
  const folder = await api.pickFolder();
  if (folder) await loadFolder(folder);
});

el.saveDraftBtn.addEventListener("click", async () => {
  if (!state.folder) return;
  await api.saveDraft(state.folder, draftFromState());
  state.dirty = false;
  el.status.textContent = "Zwischengespeichert ✔";
  setTimeout(render, 1200);
});

el.commitBtn.addEventListener("click", async () => {
  if (!state.folder) return;
  const plan = renamePlan();
  if (!plan.length) return;
  if (!confirm(`${plan.length} Datei(en) werden auf der Festplatte umbenannt. Fortfahren?`)) return;
  stopPlayer();
  const res = await api.applyRenames(state.folder, plan.map((p) => ({ from: p.from, to: p.to })));
  if (!res.ok) {
    alert("Fehler beim Umbenennen: " + res.error);
    return;
  }
  for (const p of plan) p.entry.orig = p.to; // model now matches disk
  state.dirty = false;
  await api.saveDraft(state.folder, draftFromState());
  render();
  el.status.textContent = `✅ ${res.renamed} Dateien umbenannt`;
});

el.previewBtn.addEventListener("click", async () => {
  if (!countFiles()) return;
  el.status.textContent = "Erzeuge Vorschau…";
  const res = await api.previewPdf(buildPrintHtml());
  el.status.textContent = res && res.error ? "Vorschau-Fehler: " + res.error : "";
  if (res && res.error) alert("Vorschau-Fehler: " + res.error);
});

el.pdfBtn.addEventListener("click", async () => {
  if (!countFiles()) return;
  el.status.textContent = "Erzeuge PDF…";
  const res = await api.exportPdf(buildPrintHtml());
  if (res && res.ok) el.status.textContent = "PDF gespeichert: " + res.path;
  else if (res && res.error) alert("PDF-Fehler: " + res.error);
  else el.status.textContent = "";
});

// ---------- PDF (same 5x5 / 6-line layout) ----------
function buildPrintHtml() {
  let cells = "";
  for (let vr = 0; vr < 5; vr++) {
    for (let col = 0; col < 5; col++) {
      const posIndex = (4 - vr) * 5 + col;
      const bg = cellBg(vr, col);
      if (posIndex === 24) {
        cells += `<div class="pcell blocked" style="background:${bg}"><div class="pmode">Mode</div></div>`;
        continue;
      }
      let lines = "";
      for (let b = 0; b < NUM_BANKS; b++) {
        const entry = state.slots[b * BANK_SIZE + posIndex];
        const text = entry ? escapeHtml(displayName(entry.base)) : "";
        lines += `<div class="pline"><span class="pb">${b + 1}</span><span class="pt">${text}</span></div>`;
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
  </style></head><body><div class="pgrid">${cells}</div></body></html>`;
}

// ---------- Renamer ----------
function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
function buildRegex() {
  const pat = el.rnSearch.value;
  if (!pat) return null;
  const flags = el.rnCase.checked ? "g" : "gi";
  return new RegExp(el.rnRegex.checked ? pat : escapeRegExp(pat), flags);
}
function applyReplace(base, re) {
  return base.replace(re, el.rnReplace.value);
}
function allEntries() {
  return [...state.slots.filter(Boolean), ...state.parked];
}
function refreshRenamePreview() {
  el.rnError.textContent = "";
  let re;
  try {
    re = buildRegex();
  } catch (err) {
    el.rnError.textContent = "Ungültiger Regex: " + err.message;
    el.rnApply.disabled = true;
    el.rnPreview.innerHTML = "";
    el.rnCount.textContent = "";
    return;
  }
  if (!re) {
    el.rnPreview.innerHTML = "";
    el.rnCount.textContent = "";
    el.rnApply.disabled = true;
    return;
  }
  const affected = [];
  for (const e of allEntries()) {
    const nb = applyReplace(e.base, re);
    if (nb !== e.base) affected.push([e.base, nb]);
  }
  el.rnCount.textContent = `${affected.length} betroffen`;
  el.rnApply.disabled = affected.length === 0;
  el.rnPreview.innerHTML = affected
    .map(
      ([a, b]) =>
        `<div class="rn-row"><span class="rn-old">${escapeHtml(displayName(a))}</span>` +
        `<span class="rn-arrow">→</span><span class="rn-new">${escapeHtml(displayName(b))}</span></div>`
    )
    .join("");
}
function openRenamer() {
  el.rnSearch.value = "";
  el.rnReplace.value = "";
  el.rnRegex.checked = false;
  el.rnCase.checked = false;
  refreshRenamePreview();
  el.rnDialog.classList.remove("hidden");
  el.rnSearch.focus();
}
el.renameBtn.addEventListener("click", openRenamer);
el.rnCancel.addEventListener("click", () => el.rnDialog.classList.add("hidden"));
for (const elm of [el.rnSearch, el.rnReplace, el.rnRegex, el.rnCase]) {
  elm.addEventListener("input", refreshRenamePreview);
  elm.addEventListener("change", refreshRenamePreview);
}
el.rnApply.addEventListener("click", () => {
  let re;
  try {
    re = buildRegex();
  } catch {
    return;
  }
  if (!re) return;
  for (const e of allEntries()) e.base = applyReplace(e.base, re);
  sortParked();
  el.rnDialog.classList.add("hidden");
  markDirty();
});

// ---------- SD card export ----------
el.sdBtn.addEventListener("click", openSdDialog);

async function openSdDialog() {
  const slotted = state.slots
    .map((e, i) => (e ? { orig: e.orig, name: `${pad4(prefixForSlot(i + 1))}_${e.base}` } : null))
    .filter(Boolean);
  if (!slotted.length) return;

  const res = await api.listRemovableDrives();
  const drives = (res && res.drives) || [];

  const overlay = document.createElement("div");
  overlay.className = "overlay";
  const driveRows = drives
    .map(
      (d, i) =>
        `<button class="sd-drive" data-i="${i}">💳 ${escapeHtml(d.label || d.mount)} ` +
        `<span class="muted">${escapeHtml(d.size || "")} · ${escapeHtml(d.mount)}</span></button>`
    )
    .join("");
  overlay.innerHTML = `
    <div class="dialog wide">
      <h3>Auf SD-Karte schieben (${slotted.length} Dateien)</h3>
      ${drives.length ? `<p class="muted">Wechseldatenträger:</p>${driveRows}` : `<p class="muted">Keine Wechseldatenträger erkannt.</p>`}
      <div class="dialog-buttons">
        <button id="sd-pick" class="link">📂 Ordner wählen…</button>
        <button id="sd-cancel" class="link">Abbrechen</button>
      </div>
    </div>`;
  document.body.appendChild(overlay);
  const close = () => overlay.remove();
  overlay.querySelector("#sd-cancel").onclick = close;
  overlay.querySelector("#sd-pick").onclick = async () => {
    close();
    const dir = await api.pickFolder();
    if (dir) await copyToCard(dir, slotted, null);
  };
  overlay.querySelectorAll(".sd-drive").forEach((btn) => {
    btn.onclick = async () => {
      close();
      const d = drives[Number(btn.dataset.i)];
      let doFormat = false;
      const ans = await sdFormatPrompt(d);
      if (ans === "cancel") return;
      doFormat = ans === "format";
      await copyToCard(d.mount, slotted, doFormat ? d : null);
    };
  });
}

function sdFormatPrompt(d) {
  return new Promise((resolve) => {
    const overlay = document.createElement("div");
    overlay.className = "overlay";
    overlay.innerHTML = `
      <div class="dialog">
        <h3>SD-Karte „${escapeHtml(d.label || d.mount)}"</h3>
        <p>Vor dem Kopieren formatieren? <b>Alle Daten auf der Karte gehen verloren.</b>
        Formatieren kann Administratorrechte erfordern.</p>
        <div class="dialog-buttons">
          <button id="f-yes" class="danger">Formatieren & Kopieren</button>
          <button id="f-no" class="primary">Nur kopieren</button>
        </div>
        <button id="f-cancel" class="link">Abbrechen</button>
      </div>`;
    document.body.appendChild(overlay);
    const done = (v) => {
      overlay.remove();
      resolve(v);
    };
    overlay.querySelector("#f-yes").onclick = () => done("format");
    overlay.querySelector("#f-no").onclick = () => done("copy");
    overlay.querySelector("#f-cancel").onclick = () => done("cancel");
  });
}

async function copyToCard(mount, items, driveToFormat) {
  if (driveToFormat) {
    el.status.textContent = "Formatiere…";
    const fr = await api.formatDrive(driveToFormat);
    if (!fr.ok) {
      if (fr.unsupported) {
        alert("Formatieren wird auf diesem System nicht unterstützt – kopiere ohne Formatieren.");
      } else {
        if (!confirm("Formatieren fehlgeschlagen (" + (fr.error || "") + ").\nTrotzdem kopieren?")) {
          el.status.textContent = "";
          return;
        }
      }
    }
  }
  const targetDir = mount.replace(/[\\/]+$/, "") + "/MP3";
  el.status.textContent = "Kopiere auf SD-Karte…";
  const res = await api.copyToCard(state.folder, targetDir, items);
  if (res.ok) el.status.textContent = `✅ ${res.copied} Dateien nach ${targetDir} kopiert`;
  else {
    el.status.textContent = "";
    alert("Kopieren fehlgeschlagen: " + res.error);
  }
}

// ---------- External drag & drop (load folder / add files) ----------
el.dropZone.addEventListener("dragover", (e) => {
  if (drag) return;
  e.preventDefault();
  el.dropZone.classList.add("dragover");
});
el.dropZone.addEventListener("dragleave", (e) => {
  if (e.target === el.dropZone) el.dropZone.classList.remove("dragover");
});
el.dropZone.addEventListener("drop", async (e) => {
  if (drag) return;
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
    await reloadKeepingModel();
  } else {
    await loadFolder(mp3s[0].dir);
  }
});

// Test hook (used by the headless capture/smoke scripts; harmless in normal use).
window.__sbTest = { loadFolder, get state() { return state; } };
