// Regression test for ERR_PACKAGE_PATH_NOT_EXPORTED:
// music-metadata v11+ is ESM-only and cannot be loaded via require() in
// Electron's CommonJS main process. This test ensures every entry in
// package.json "dependencies" can be require()'d without error.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const pkg = require("../package.json");

for (const name of Object.keys(pkg.dependencies || {})) {
  test(`dependency "${name}" is require()-able (not ESM-only)`, () => {
    let mod;
    try {
      mod = require(name);
    } catch (err) {
      // Surface a clear failure message so the root cause is obvious.
      assert.fail(
        `require("${name}") threw ${err.code || err.name}: ${err.message}\n` +
          `Hint: the package may be ESM-only. Downgrade to a CJS-compatible version ` +
          `or use dynamic import() in main.js.`
      );
    }
    // The module must export something (not undefined/null).
    assert.ok(mod != null, `require("${name}") returned ${mod}`);
  });
}
