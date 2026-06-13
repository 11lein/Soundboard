// Electron smoke test: loads the real index.html with the real preload and
// verifies window.api is fully exposed and the IPC round-trips work. This is
// the regression guard for "Ordner öffnen geht nicht mehr" (a broken preload
// leaves window.api undefined, so listMp3/pickFolder silently do nothing).
process.env.MP3SORTER_NO_WINDOW = "1";

const { app, BrowserWindow } = require("electron");
const path = require("path");
const fs = require("fs");
const os = require("os");

require("../main.js"); // registers all IPC handlers (no window due to the guard)

app.whenReady().then(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mp3smoke-"));
  fs.writeFileSync(path.join(dir, "0002_b.mp3"), "x");
  fs.writeFileSync(path.join(dir, "apple.mp3"), "x");

  const errors = [];
  const win = new BrowserWindow({
    show: false,
    webPreferences: {
      preload: path.join(__dirname, "..", "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.webContents.on("preload-error", (_e, _p, err) => {
    errors.push("preload-error: " + (err && err.message));
  });
  win.webContents.on("console-message", (...args) => {
    const a = args.length >= 3 ? { level: args[1], message: args[2] } : args[0];
    if (a && (a.level === 3 || a.level === "error")) errors.push(a.message || "");
  });

  await win.loadFile(path.join(__dirname, "..", "renderer", "index.html"));

  const r = await win.webContents.executeJavaScript(`(async () => {
    const a = window.api;
    const out = { hasApi: !!a, keys: a ? Object.keys(a) : [] };
    if (a) {
      out.colorsRows = a.colors && a.colors.rows ? a.colors.rows.length : 0;
      out.bottomRow = a.colors && a.colors.rows ? a.colors.rows[4] : null;
      out.files = await a.listMp3(${JSON.stringify(dir)});
      out.url = await a.fileUrl(${JSON.stringify(dir)}, "apple.mp3");
      out.hasOpenBtn = !!document.getElementById("open-btn");
      out.preview = await a.previewPdf("<!doctype html><html><body><div>x</div></body></html>");
    }
    return out;
  })()`);

  const checks = [];
  const ok = (name, cond) => checks.push({ name, cond: !!cond });
  ok("window.api exposed", r.hasApi);
  ok("api.pickFolder present", r.keys.includes("pickFolder"));
  ok("api.listMp3 present", r.keys.includes("listMp3"));
  ok("api.fileUrl present", r.keys.includes("fileUrl"));
  ok("api.colors present", r.keys.includes("colors"));
  ok("colours have 5 rows", r.colorsRows === 5);
  ok(
    "bottom row = black,red,black,black,black",
    JSON.stringify(r.bottomRow) ===
      JSON.stringify(["black", "red", "black", "black", "black"])
  );
  ok(
    "listMp3 returns both files (open-folder path works)",
    r.files && r.files.includes("0002_b.mp3") && r.files.includes("apple.mp3")
  );
  ok("fileUrl returns a file:// URL", typeof r.url === "string" && r.url.startsWith("file://"));
  ok("open button rendered", r.hasOpenBtn);
  ok("previewPdf renders & opens", r.preview && r.preview.ok === true);
  ok("no preload/renderer errors", errors.length === 0);

  let failed = 0;
  for (const c of checks) {
    console.log((c.cond ? "PASS" : "FAIL") + " — " + c.name);
    if (!c.cond) failed++;
  }
  if (errors.length) console.log("captured errors:", errors);

  fs.rmSync(dir, { recursive: true, force: true });
  BrowserWindow.getAllWindows().forEach((w) => !w.isDestroyed() && w.destroy());
  console.log(failed ? `\n${failed} check(s) FAILED` : "\nAll smoke checks passed ✔");
  app.exit(failed ? 1 : 0);
});
