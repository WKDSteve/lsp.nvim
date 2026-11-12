-- TESTS/sheets/features.lua -- the functionalities of lsp.nvim as its user meets them; `testing sheets report`
-- says which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that names
-- an id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The list follows docs/FEATURES/ (README.md and its pages).
return {
  -- Configuration and servers
  {
    id = "lsp.config-layers",
    title = "Defaults, preset, setup() and a .nvim-lsp.json per project; every warning names its layer",
    docs = "docs/FEATURES/CONFIGURATION.md",
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
  },
  {
    id = "lsp.doctor",
    title = ":LspDoctor says which servers are expected, running and resolvable, and where the chain breaks",
    docs = "docs/FEATURES/DOCTOR.md",
  },
  {
    id = "lsp.formatter",
    title = "Conform first with an LSP fallback; format-on-save keeps every window's view",
    docs = "docs/FEATURES/FORMATTER.md",
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
  },
  {
    id = "lsp.type-hierarchy",
    title = "lsh and lsH show the supertypes and the subtypes",
    docs = "docs/FEATURES/NAVIGATION.md",
  },
  {
    id = "lsp.outline",
    title = "<leader>xo toggles the symbol tree of the document",
    docs = "docs/FEATURES/NAVIGATION.md",
  },
  {
    id = "lsp.lua-root",
    title = "<leader>gtt jumps from inside a nested Lua table or function to its structure root",
    docs = "docs/FEATURES/NAVIGATION.md",
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
  },
  {
    id = "lsp.code-action-indicator",
    title = "The line is marked when the server has code actions of the allowed kinds there, before lsa is pressed",
    docs = "docs/FEATURES/INDICATORS.md",
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
  },
  {
    id = "lsp.workspace-diagnostics",
    title = "A toggle fills the diagnostics of the whole workspace on attach",
    docs = "docs/FEATURES/DIAGNOSTICS.md",
  },
  -- Tools and integrations
  {
    id = "lsp.extras",
    title = "ESLint/Prettier, signature help and the TypeScript type lookup",
    docs = "docs/FEATURES/TOOLS.md",
  },
  {
    id = "lsp.completion-source",
    title = "A completion source for nvim-cmp or blink completes dotted plugin names, ranked by use",
    docs = "docs/FEATURES/TOOLS.md",
  },
  {
    id = "lsp.context-menu",
    title = "The right-click menu offers the LSP keymaps as entries",
    docs = "docs/FEATURES/INTEGRATIONS.md",
  },
}
