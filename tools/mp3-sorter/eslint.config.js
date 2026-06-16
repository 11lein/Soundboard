// ESLint flat config (ESLint v9+). Three environments live in this project:
//   - Electron main / preload / tests  -> Node (CommonJS)
//   - lib/*.js                          -> UMD modules used in BOTH Node and the
//                                          browser, so they need both global sets
//   - renderer/*.js                     -> browser, classic <script> scope, plus
//                                          the globals injected by naming.js,
//                                          dialog.js and the preload `api` bridge
const js = require("@eslint/js");
const globals = require("globals");

module.exports = [
  { ignores: ["node_modules/**", "dist/**"] },
  js.configs.recommended,
  {
    files: ["main.js", "preload.js", "test/**/*.js", "eslint.config.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "commonjs",
      globals: { ...globals.node },
    },
  },
  {
    // UMD helpers: detect their environment at runtime, so allow both.
    files: ["lib/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "commonjs",
      globals: { ...globals.node, ...globals.browser },
    },
  },
  {
    // Browser, classic <script> scope. The cross-file globals (naming, api,
    // showDialog) are declared per-file via `/* global ... */` directives, so we
    // don't predeclare them here (that would clash with dialog.js, which *defines*
    // showDialog).
    files: ["renderer/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script",
      globals: { ...globals.browser },
    },
  },
];
