// Defence-in-depth path helper for IPC handlers.
//
// Every file operation triggered from the renderer joins a folder (chosen by the
// user via the OS dialog) with a *filename* that the renderer supplies. Those
// filenames are normally plain basenames taken from a directory listing, so they
// are harmless. But the main process must not trust the renderer blindly: a bug
// (or a compromised renderer) could pass a crafted name like "../../secret" and
// make us read/delete/overwrite files outside the chosen folder.
//
// safeJoin() collapses the name to its basename and asserts the result really is
// a direct child of `folder`, throwing otherwise. Using it everywhere keeps the
// blast radius of any file operation limited to the folder the user picked.
(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory(require("path"));
  } else {
    root.safePath = factory(root.path);
  }
})(typeof self !== "undefined" ? self : this, function (path) {
  // Join `name` onto `folder`, guaranteeing the result is a file directly inside
  // `folder` (no "../" escape, no nested subdirectory). Throws on violation.
  function safeJoin(folder, name) {
    if (typeof folder !== "string" || !folder) throw new Error("invalid folder");
    if (typeof name !== "string" || !name) throw new Error("invalid name");
    // basename() drops any directory component, so "../x" and "a/b" become "x"/"b".
    const full = path.resolve(folder, path.basename(name));
    // After resolving, the parent directory must be exactly the chosen folder.
    if (path.dirname(full) !== path.resolve(folder)) {
      throw new Error(`unsafe path: ${name}`);
    }
    return full;
  }

  return { safeJoin };
});
