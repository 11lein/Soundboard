const { app, BrowserWindow, ipcMain, dialog } = require("electron");
const path = require("path");
const fs = require("fs/promises");
const os = require("os");
const { execFile } = require("child_process");
const { promisify } = require("util");
const { pathToFileURL } = require("url");
const naming = require("./lib/naming");
const keyColors = require("./lib/key-colors.json");
const mm = require("music-metadata");

const execFileP = promisify(execFile);

const DRAFT_FILE = ".mp3sorter.json"; // intermediate state, lives in the folder

// App config (remembers the last opened folder across launches).
const CONFIG_FILE = path.join(app.getPath("userData"), "mp3sorter-config.json");
async function readConfig() {
  try {
    return JSON.parse(await fs.readFile(CONFIG_FILE, "utf8"));
  } catch {
    return {};
  }
}
async function writeConfig(patch) {
  const cfg = { ...(await readConfig()), ...patch };
  try {
    await fs.writeFile(CONFIG_FILE, JSON.stringify(cfg, null, 2), "utf8");
  } catch {
    /* ignore – config is best-effort */
  }
}

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

// --- IPC: list .mp3 files in a folder (also remembers it as the last folder) ---
ipcMain.handle("list-mp3", async (_e, folder) => {
  const entries = await fs.readdir(folder, { withFileTypes: true });
  writeConfig({ lastFolder: folder }); // remember for next launch
  return entries
    .filter((d) => d.isFile() && d.name.toLowerCase().endsWith(".mp3"))
    .map((d) => d.name);
});

// --- IPC: the last opened folder (if it still exists) ---
ipcMain.handle("get-last-folder", async () => {
  const cfg = await readConfig();
  if (!cfg.lastFolder) return null;
  try {
    const st = await fs.stat(cfg.lastFolder);
    return st.isDirectory() ? cfg.lastFolder : null;
  } catch {
    return null;
  }
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

// --- IPC: export the track list (number -> title) as JSON ---
ipcMain.handle("export-list", async (_e, defaultName, json) => {
  // Always drop a copy into the app's assets, so the next app build bundles the
  // latest list and the phone can import it without copying a file around.
  try {
    const appCopy = path.join(__dirname, "..", "..", "app", "assets", "tracklist.json");
    await fs.writeFile(appCopy, json, "utf8");
  } catch {
    /* ignore – e.g. running from a packaged build without the repo layout */
  }
  const save = await dialog.showSaveDialog({
    defaultPath: defaultName,
    filters: [{ name: "JSON", extensions: ["json"] }],
  });
  if (save.canceled || !save.filePath) return { ok: false };
  try {
    await fs.writeFile(save.filePath, json, "utf8");
    return { ok: true, path: save.filePath };
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }
});

// --- IPC: import a track list (number -> title) JSON for renaming ---
ipcMain.handle("import-list", async () => {
  const res = await dialog.showOpenDialog({
    properties: ["openFile"],
    filters: [{ name: "JSON", extensions: ["json"] }],
  });
  if (res.canceled || !res.filePaths.length) return { ok: false, canceled: true };
  try {
    const raw = await fs.readFile(res.filePaths[0], "utf8");
    const data = JSON.parse(raw);
    if (!data || !Array.isArray(data.tracks)) {
      return { ok: false, error: "Keine gültige Listendatei (tracks fehlt)." };
    }
    return { ok: true, tracks: data.tracks };
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

// --- IPC: apply a rename plan (two-phase to avoid collisions) ---
// plan: array of { from, to } filenames within `folder`.
ipcMain.handle("apply-renames", async (_e, folder, plan) => {
  // Detect duplicate target names up front.
  const targets = new Set();
  for (const p of plan) {
    if (targets.has(p.to)) return { ok: false, error: `Doppelter Zielname: ${p.to}` };
    targets.add(p.to);
  }

  const toRename = plan.filter((p) => p.from !== p.to);
  const tmpSuffix = `.mp3sorter.tmp.${process.pid}`;

  try {
    // Phase 1: move every changing file to a unique temp name.
    for (let i = 0; i < toRename.length; i++) {
      await fs.rename(
        path.join(folder, toRename[i].from),
        path.join(folder, `__${i}${tmpSuffix}`)
      );
    }
    // Phase 2: move temp names to their final names.
    for (let i = 0; i < toRename.length; i++) {
      await fs.rename(
        path.join(folder, `__${i}${tmpSuffix}`),
        path.join(folder, toRename[i].to)
      );
    }
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }
  return { ok: true, renamed: toRename.length };
});

// --- IPC: list removable drives (best-effort, per OS) ---
ipcMain.handle("list-removable-drives", async () => {
  try {
    if (process.platform === "linux") {
      const { stdout } = await execFileP("lsblk", [
        "-J", "-o", "NAME,SIZE,TYPE,RM,MOUNTPOINT,LABEL,PATH",
      ]);
      const data = JSON.parse(stdout);
      const out = [];
      const walk = (nodes) => {
        for (const n of nodes || []) {
          if (n.rm && n.mountpoint && n.type === "part") {
            out.push({
              label: n.label || n.name,
              size: n.size,
              mount: n.mountpoint,
              device: n.path,
            });
          }
          if (n.children) walk(n.children);
        }
      };
      walk(data.blockdevices);
      return { ok: true, drives: out };
    }
    if (process.platform === "win32") {
      const { stdout } = await execFileP("wmic", [
        "logicaldisk", "where", "drivetype=2", "get", "deviceid,volumename,size", "/format:csv",
      ]);
      const drives = stdout
        .split(/\r?\n/).slice(1).map((l) => l.trim()).filter(Boolean)
        .map((l) => l.split(","))
        .filter((c) => c.length >= 4)
        .map((c) => ({ label: c[3] || c[1], size: c[2], mount: c[1] + "\\", device: c[1] }));
      return { ok: true, drives };
    }
    if (process.platform === "darwin") {
      const { stdout } = await execFileP("df", ["-l"]);
      const drives = stdout
        .split("\n").slice(1)
        .filter((l) => l.includes("/Volumes/"))
        .map((l) => {
          const m = l.match(/^(\S+).*\s(\/Volumes\/.+)$/);
          return m ? { label: path.basename(m[2]), size: "", mount: m[2], device: m[1] } : null;
        })
        .filter(Boolean);
      return { ok: true, drives };
    }
    return { ok: true, drives: [] };
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err), drives: [] };
  }
});

// --- IPC: format a removable drive as FAT32 (best-effort, may need privileges) ---
ipcMain.handle("format-drive", async (_e, drive) => {
  try {
    if (process.platform === "linux") {
      // Unmount then mkfs.vfat (needs privileges; reports clearly if not allowed).
      await execFileP("umount", [drive.device]).catch(() => {});
      await execFileP("mkfs.vfat", ["-F", "32", "-n", "SOUNDBOARD", drive.device]);
      return { ok: true };
    }
    if (process.platform === "darwin") {
      await execFileP("diskutil", ["eraseVolume", "MS-DOS", "SOUNDBOARD", drive.device]);
      return { ok: true };
    }
    if (process.platform === "win32") {
      const letter = String(drive.device).replace(/\\$/, "");
      await execFileP("cmd", ["/c", "format", letter, "/FS:FAT32", "/Q", "/Y", "/V:SOUNDBOARD"]);
      return { ok: true };
    }
    return { ok: false, unsupported: true };
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }
});

// --- IPC: delete files from a folder ---
ipcMain.handle("delete-files", async (_e, folder, names) => {
  const deleted = [];
  const failed = [];
  for (const name of names) {
    try {
      await fs.unlink(path.join(folder, name));
      deleted.push(name);
    } catch (err) {
      failed.push({ name, error: String(err && err.message ? err.message : err) });
    }
  }
  return { ok: failed.length === 0, deleted, failed };
});

// --- IPC: read MP3 duration and bitrate ---
ipcMain.handle("mp3-info", async (_e, folder, name) => {
  try {
    const meta = await mm.parseFile(path.join(folder, name), { duration: true });
    const dur = meta.format.duration || 0;
    const br = meta.format.bitrate ? Math.round(meta.format.bitrate / 1000) : null;
    const mins = Math.floor(dur / 60);
    const secs = Math.floor(dur % 60).toString().padStart(2, "0");
    return { ok: true, duration: `${mins}:${secs}`, bitrate: br ? `${br} kbps` : null };
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }
});

// --- IPC: copy files to the SD card ---
// srcFolder: source folder; targetDir: destination (e.g. card mount + /MP3)
// items: [{ orig (source filename), name (target filename) }]
ipcMain.handle("copy-to-card", async (_e, srcFolder, targetDir, items) => {
  try {
    await fs.mkdir(targetDir, { recursive: true });
    let copied = 0;
    for (const it of items) {
      await fs.copyFile(
        path.join(srcFolder, it.orig),
        path.join(targetDir, it.name)
      );
      copied++;
    }
    return { ok: true, copied };
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }
});
