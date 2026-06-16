const { contextBridge, ipcRenderer, webUtils } = require("electron");

contextBridge.exposeInMainWorld("api", {
  // Loaded in the main process; sync IPC works even in a sandboxed preload.
  colors: ipcRenderer.sendSync("get-colors"),
  fileUrl: (folder, name) => ipcRenderer.invoke("file-url", folder, name),
  pickFolder: () => ipcRenderer.invoke("pick-folder"),
  listMp3: (folder) => ipcRenderer.invoke("list-mp3", folder),
  getLastFolder: () => ipcRenderer.invoke("get-last-folder"),
  loadDraft: (folder) => ipcRenderer.invoke("load-draft", folder),
  saveDraft: (folder, state) => ipcRenderer.invoke("save-draft", folder, state),
  applyRenames: (folder, plan) =>
    ipcRenderer.invoke("apply-renames", folder, plan),
  listRemovableDrives: () => ipcRenderer.invoke("list-removable-drives"),
  formatDrive: (drive) => ipcRenderer.invoke("format-drive", drive),
  copyToCard: (srcFolder, targetDir, items) =>
    ipcRenderer.invoke("copy-to-card", srcFolder, targetDir, items),
  inspectPaths: (paths) => ipcRenderer.invoke("inspect-paths", paths),
  copyInto: (folder, paths) => ipcRenderer.invoke("copy-into", folder, paths),
  exportPdf: (html) => ipcRenderer.invoke("export-pdf", html),
  exportList: (defaultName, json) =>
    ipcRenderer.invoke("export-list", defaultName, json),
  saveAppList: (json) => ipcRenderer.invoke("save-app-list", json),
  importList: () => ipcRenderer.invoke("import-list"),
  previewPdf: (html) => ipcRenderer.invoke("preview-pdf", html),
  deleteFiles: (folder, names) => ipcRenderer.invoke("delete-files", folder, names),
  mp3Info: (folder, name) => ipcRenderer.invoke("mp3-info", folder, name),
  // Resolve a dropped File object to its absolute path (Electron 32+ API).
  pathForFile: (file) => {
    try {
      return webUtils.getPathForFile(file);
    } catch {
      return null;
    }
  },
});
