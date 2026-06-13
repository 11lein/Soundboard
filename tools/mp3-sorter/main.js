const { app, BrowserWindow, ipcMain, dialog } = require("electron");
const path = require("path");
const fs = require("fs/promises");
const os = require("os");
const { pathToFileURL } = require("url");
const naming = require("./lib/naming");
const keyColors = require("./lib/key-colors.json");

const DRAFT_FILE = ".mp3sorter.json"; // intermediate state, lives in the folder

// 2D-only UI: no GPU needed. Disabling HW acceleration avoids harmless but noisy
// "GetVSyncParametersIfAvailable() failed" GL warnings on Linux/VMs.
app.disableHardwareAcceleration();

function createWindow() {
  const win = new BrowserWindow({
    width: 1100,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.loadFile(path.join(__dirname, "renderer", "index.html"));
  return win;
}

app.whenReady().then(() => {
  // The smoke test requires this file only to register the IPC handlers; it
  // sets MP3SORTER_NO_WINDOW so no real window pops up during the test run.
  if (process.env.MP3SORTER_NO_WINDOW) return;
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

// --- IPC: key colours (sync, so preload can expose them immediately) ---
ipcMain.on("get-colors", (e) => {
  e.returnValue = keyColors;
});

// --- IPC: cross-platform file:// URL for a folder + filename ---
ipcMain.handle("file-url", (_e, folder, name) =>
  pathToFileURL(path.join(folder, name)).href
);

// --- IPC: pick a folder ---
ipcMain.handle("pick-folder", async () => {
  const res = await dialog.showOpenDialog({ properties: ["openDirectory"] });
  if (res.canceled || !res.filePaths.length) return null;
  return res.filePaths[0];
});

// --- IPC: list .mp3 files in a folder ---
ipcMain.handle("list-mp3", async (_e, folder) => {
  const entries = await fs.readdir(folder, { withFileTypes: true });
  return entries
    .filter((d) => d.isFile() && d.name.toLowerCase().endsWith(".mp3"))
    .map((d) => d.name);
});

// --- IPC: inspect dropped paths (file vs directory) ---
ipcMain.handle("inspect-paths", async (_e, paths) => {
  const out = [];
  for (const p of paths) {
    if (!p) continue;
    try {
      const st = await fs.stat(p);
      out.push({
        path: p,
        name: path.basename(p),
        dir: path.dirname(p),
        isDir: st.isDirectory(),
      });
    } catch {
      /* ignore unreadable entries */
    }
  }
  return out;
});

// --- IPC: copy dropped mp3 files into the target folder ---
ipcMain.handle("copy-into", async (_e, folder, paths) => {
  let copied = 0;
  for (const p of paths) {
    if (!p || !p.toLowerCase().endsWith(".mp3")) continue;
    const dest = path.join(folder, path.basename(p));
    if (path.resolve(p) === path.resolve(dest)) continue; // already there
    try {
      await fs.copyFile(p, dest);
      copied++;
    } catch {
      /* skip files we cannot copy */
    }
  }
  return copied;
});

// --- IPC: load the draft (intermediate) state if present ---
ipcMain.handle("load-draft", async (_e, folder) => {
  try {
    const raw = await fs.readFile(path.join(folder, DRAFT_FILE), "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
});

// --- IPC: save the draft (intermediate) state ---
ipcMain.handle("save-draft", async (_e, folder, state) => {
  const payload = { savedAt: new Date().toISOString(), ...state };
  await fs.writeFile(
    path.join(folder, DRAFT_FILE),
    JSON.stringify(payload, null, 2),
    "utf8"
  );
  return true;
});

// Render an HTML string to an A4-landscape PDF buffer (offscreen).
async function htmlToPdf(html) {
  const win = new BrowserWindow({ show: false });
  try {
    await win.loadURL("data:text/html;charset=utf-8," + encodeURIComponent(html));
    return await win.webContents.printToPDF({
      landscape: true,
      pageSize: "A4",
      printBackground: true,
    });
  } finally {
    win.destroy();
  }
}

// --- IPC: export the assignment as an A4-landscape PDF ---
ipcMain.handle("export-pdf", async (_e, html) => {
  const save = await dialog.showSaveDialog({
    defaultPath: "soundboard-belegung.pdf",
    filters: [{ name: "PDF", extensions: ["pdf"] }],
  });
  if (save.canceled || !save.filePath) return { ok: false };
  try {
    await fs.writeFile(save.filePath, await htmlToPdf(html));
    return { ok: true, path: save.filePath };
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }
});

// --- IPC: render the PDF to a temp file and show it in a preview window ---
let previewWin = null;
ipcMain.handle("preview-pdf", async (_e, html) => {
  try {
    const tmp = path.join(os.tmpdir(), "mp3sorter-preview.pdf");
    await fs.writeFile(tmp, await htmlToPdf(html));
    if (previewWin && !previewWin.isDestroyed()) previewWin.close();
    previewWin = new BrowserWindow({
      width: 1000,
      height: 720,
      title: "PDF-Vorschau",
    });
    // cache-buster so a re-preview reloads the freshly written file
    await previewWin.loadURL(pathToFileURL(tmp).href + "?t=" + Date.now());
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }
});

// --- IPC: commit renames (two-phase to avoid collisions) ---
// order: array of original filenames in slot order (index 0 -> slot 1)
ipcMain.handle("commit-rename", async (_e, folder, order) => {
  // Plan: original name -> final name.
  const plan = order.map((orig, i) => ({
    orig,
    final: naming.finalName(i + 1, orig),
  }));

  // Skip no-ops; detect duplicate target names up front.
  const targets = new Set();
  for (const p of plan) {
    if (targets.has(p.final)) {
      return { ok: false, error: `Doppelter Zielname: ${p.final}` };
    }
    targets.add(p.final);
  }

  const toRename = plan.filter((p) => p.orig !== p.final);
  const tmpSuffix = `.mp3sorter.tmp.${process.pid}`;

  try {
    // Phase 1: move every file that changes to a unique temp name.
    for (let i = 0; i < toRename.length; i++) {
      await fs.rename(
        path.join(folder, toRename[i].orig),
        path.join(folder, `__${i}${tmpSuffix}`)
      );
    }
    // Phase 2: move temp names to their final names.
    for (let i = 0; i < toRename.length; i++) {
      await fs.rename(
        path.join(folder, `__${i}${tmpSuffix}`),
        path.join(folder, toRename[i].final)
      );
    }
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }

  // Refresh the draft so it reflects the now-renamed files.
  const newOrder = plan.map((p) => p.final);
  await fs.writeFile(
    path.join(folder, DRAFT_FILE),
    JSON.stringify(
      { savedAt: new Date().toISOString(), order: newOrder },
      null,
      2
    ),
    "utf8"
  );
  return { ok: true, renamed: toRename.length, order: newOrder };
});
