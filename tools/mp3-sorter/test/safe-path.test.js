const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { safeJoin } = require("../lib/safe-path");

const FOLDER = path.resolve("/music");

test("safeJoin returns a direct child of the folder", () => {
  assert.equal(safeJoin(FOLDER, "0101_horn.mp3"), path.join(FOLDER, "0101_horn.mp3"));
});

test("safeJoin strips directory components to the basename", () => {
  // A nested path collapses to its file name inside the folder (no subdir escape).
  assert.equal(safeJoin(FOLDER, "sub/dir/x.mp3"), path.join(FOLDER, "x.mp3"));
});

test("safeJoin neutralises ../ traversal (collapses to basename in-folder)", () => {
  // "../../etc/passwd" -> basename "passwd" -> stays inside the folder.
  assert.equal(safeJoin(FOLDER, "../../etc/passwd"), path.join(FOLDER, "passwd"));
});

test("safeJoin rejects names that resolve to nothing in-folder", () => {
  assert.throws(() => safeJoin(FOLDER, ".."), /unsafe path|invalid/);
  assert.throws(() => safeJoin(FOLDER, "."), /unsafe path|invalid/);
});

test("safeJoin rejects empty/invalid inputs", () => {
  assert.throws(() => safeJoin("", "x.mp3"), /invalid folder/);
  assert.throws(() => safeJoin(FOLDER, ""), /invalid name/);
  assert.throws(() => safeJoin(FOLDER, null), /invalid name/);
});
