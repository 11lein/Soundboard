const { contextBridge, ipcRenderer, webUtils } = require("electron");

contextBridge.exposeInMainWorld("api", {
  // Loaded in the main process; sync IPC works even in a sandboxed preload.
  colors: ipcRenderer.sendSync("get-colors"),
  fileUrl: (folder, name) => ipcRenderer.invoke("file-url", folder, name),
  pickFolder: () => ipcRenderer.invoke("pick-folder"),
  listMp3: (folder) => ipcRenderer.invoke("list-mp3", folder),
  loadDraft: (folder) => ipcRenderer.invoke("load-draft", folder),
  saveDraft: (folder, state) => ipcRenderer.invoke("save-draft", folder, state),
  commitRename: (folder, order) =>
    ipcRenderer.invoke("commit-rename", folder, order),
  inspectPaths: (paths) => ipcRenderer.invoke("inspect-paths", paths),
  copyInto: (folder, paths) => ipcRenderer.invoke("copy-into", folder, paths),
  exportPdf: (html) => ipcRenderer.invoke("export-pdf", html),
  previewPdf: (html) => ipcRenderer.invoke("preview-pdf", html),
  // Resolve a dropped File object to its absolute path (Electron 32+ API).
  pathForFile: (file) => {
    try {
      return webUtils.getPathForFile(file);
    } catch {
      return null;
    }
  },
});
