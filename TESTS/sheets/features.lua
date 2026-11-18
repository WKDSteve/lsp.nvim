-- TESTS/sheets/features.lua -- the functionalities of lsp.nvim as its user meets them; `testing sheets report`
-- says which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that names
-- an id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The list follows docs/FEATURES/ (README.md and its pages).
--
-- `perf` (testing.nvim docs/PERF.md) says why `testing perf` does not measure a functionality through a sheet of
-- its own: "user" = only the installed config shows its processes (a plugin of the config starts them: conform's
-- formatters, fzf-lua's fzf, lensline's git, gitsigns' git); "skip:no process of its own" = the functionality
-- talks to the attached servers or works in the editor and starts nothing; what starting a server costs is
-- measured once, by lsp.server-start-stop (catalog `lsp.servers`).
return {
  -- Configuration and servers
  {
    id = "lsp.config-layers",
    title = "Defaults, preset, setup() and a .nvim-lsp.json per project; every warning names its layer",
    docs = "docs/FEATURES/CONFIGURATION.md",
    perf = "skip:no process of its own: merges tables and reads .nvim-lsp.json in the editor",
  },
  {
    id = "lsp.servers",
    title = "The configured servers are registered with their capabilities, attach hooks and per-language setup",
    docs = "docs/FEATURES/SERVERS.md",
  },
  {
    id = "lsp.restart",
    title = "A crashed server restarts on its own; :LspRestartHere and :LspStopHere act on the real servers of a buffer",
    docs = "docs/FEATURES/SERVERS.md",
  },
  {
    id = "lsp.workspace",
    title = "The root scope (cwd, git root, file) and the workspace folders decide what a server sees as the project",
    docs = "docs/FEATURES/WORKSPACE.md",
    perf = "skip:no process of its own: the root and the folders are found in the editor (vim.fs.root, the clients' workspace folders)",
  },
  {
    id = "lsp.doctor",
    title = ":LspDoctor says which servers are expected, running and resolvable, and where the chain breaks",
    docs = "docs/FEATURES/DOCTOR.md",
    perf = "skip:no process of its own: reads the clients and resolves executables on PATH; the probe attaches running clients and never starts a server",
  },
  {
    id = "lsp.formatter",
    title = "Conform first with an LSP fallback; format-on-save keeps every window's view",
    docs = "docs/FEATURES/FORMATTER.md",
    perf = "user",
  },
  -- Navigation
  {
    id = "lsp.peek",
    title = "The definition opens in a float; the peeked buffer is taken over with <C-o>, <C-v>, <C-x> or <C-t>",
    docs = "docs/FEATURES/NAVIGATION.md",
  },
  {
    id = "lsp.code-actions",
    title = "lsa lists the code actions at the cursor and gra for a selection, with the edit previewed as a diff",
    docs = "docs/FEATURES/NAVIGATION.md",
  },
  {
    id = "lsp.finder",
    title = "lsf shows everything that uses, implements or defines the symbol in one picker",
    docs = "docs/FEATURES/NAVIGATION.md",
    perf = "user",
  },
  {
    id = "lsp.type-hierarchy",
    title = "lsh and lsH show the supertypes and the subtypes",
    docs = "docs/FEATURES/NAVIGATION.md",
    perf = "skip:no process of its own: LSP requests to the attached servers",
  },
  {
    id = "lsp.outline",
    title = "<leader>xo toggles the symbol tree of the document",
    docs = "docs/FEATURES/NAVIGATION.md",
    perf = "skip:no process of its own: the symbol tree of Trouble over the attached servers",
  },
  {
    id = "lsp.lua-root",
    title = "<leader>gtt jumps from inside a nested Lua table or function to its structure root",
    docs = "docs/FEATURES/NAVIGATION.md",
    perf = "skip:no process of its own: a tree-sitter walk in the editor",
  },
  {
    id = "lsp.gitsigns-actions",
    title = "gitsigns' hunk actions (stage, reset, preview) are code actions of lsa and gra, also on a selection",
    docs = "docs/FEATURES/NAVIGATION.md",
    -- lsp.gitsigns-hunk-actions checks it with the gitsigns of the installed config (a skip where there is none)
    perf = "user",
  },
  {
    id = "lsp.env-links",
    title = "A link with an environment variable resolves as a document link; gx opens its target",
    docs = "docs/FEATURES/SERVERS.md",
  },
  -- Indicators
  {
    id = "lsp.inlay-hints",
    title = "Inlay hints on or off globally and per filetype, for every loaded buffer and later ones",
    docs = "docs/FEATURES/INDICATORS.md",
    perf = "skip:no process of its own: LSP requests to the attached servers",
  },
  {
    id = "lsp.code-action-indicator",
    title = "The line is marked when the server has code actions of the allowed kinds there, before lsa is pressed",
    docs = "docs/FEATURES/INDICATORS.md",
    perf = "skip:no process of its own: LSP requests to the attached servers",
  },
  {
    id = "lsp.breadcrumb",
    title = "The winbar shows folder > file > symbols at the cursor, with a clean separator",
    docs = "docs/FEATURES/INDICATORS.md",
  },
  {
    id = "lsp.implementation-markers",
    title = "An interface shows how often it is implemented at the end of its line, and the marker follows edits",
    docs = "docs/FEATURES/INDICATORS.md",
  },
  -- Diagnostics
  {
    id = "lsp.diagnostics",
    title = "Diagnostics into the quickfix or location list, and a step to the next or previous one",
    docs = "docs/FEATURES/DIAGNOSTICS.md",
    perf = "skip:no process of its own: vim.diagnostic into the quickfix or location list",
  },
  {
    id = "lsp.workspace-diagnostics",
    title = "A toggle fills the diagnostics of the whole workspace on attach",
    docs = "docs/FEATURES/DIAGNOSTICS.md",
    perf = "skip:no process of its own: LSP requests to the attached servers",
  },
  -- Tools and integrations
  {
    id = "lsp.extras",
    title = "ESLint/Prettier, signature help and the TypeScript type lookup",
    docs = "docs/FEATURES/TOOLS.md",
  },
  {
    id = "lsp.help-word",
    title = ":Lsp help and its key show the help of the word under the cursor, per-filetype help pages first",
    docs = "docs/FEATURES/TOOLS.md",
  },
  {
    id = "lsp.completion-source",
    title = "A completion source for nvim-cmp or blink completes dotted plugin names, ranked by use",
    docs = "docs/FEATURES/TOOLS.md",
    perf = "skip:no process of its own: a completion source in the editor",
  },
  {
    id = "lsp.lensline",
    title = "lensline (the LSP pack) shows the usages of the focused function inline, without running git blame",
    docs = "docs/installation.md",
    -- lensline is a plugin of the pack: lsp.lensline-user-config checks it on the installed config
    perf = "user",
  },
  -- Languages
  {
    id = "lsp.astro-commands",
    title = ":AstroDevStop ends the dev server and :AstroBuild builds the project and shows its output",
    docs = "docs/BINDINGS.md",
  },
  {
    id = "lsp.flutter-run",
    title = "<leader>fr in a Dart file runs flutter run in a terminal split from the project root, or focuses it",
  },
  {
    id = "lsp.context-menu",
    title = "The right-click menu offers the LSP keymaps as entries",
    docs = "docs/FEATURES/INTEGRATIONS.md",
    perf = "skip:no process of its own: menu entries for the keymaps",
  },
}
