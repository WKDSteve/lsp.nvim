-- What of the live checks A1-A11 (and gx) of the lspsaga replacements no machine can see (task
-- lsp.nvim/live-check-lspsaga-replacements). Everything else is a sheet of this folder or a case of
-- TESTS/lsp/pty_fzf_spec.lua (a real fzf window in tmux). These need YOUR tools: real language servers, your
-- plugin set, your font and the program that opens a link.
return {
  id = "lsp.lspsaga-by-hand",
  title = "lsp.nvim: the lspsaga live checks that need your real tools",
  task = "lsp.nvim/live-check-lspsaga-replacements",
  engine = "manual",
  manual = {
    "A1 with a real tsserver in your config: `lsa` on line 1 of a .ts file lists the real actions with a diff preview, and the chosen one is applied (the window itself is covered by the stub-server terminal spec)",
    'A2 with a real tsserver: `gra` on lines 4-6 of the example in the report lists "Extract function"',
    'A4 in the fzf window: `lsa` on a changed line lists "gitsigns: Stage hunk" in the real picker (the hunk actions and the staging are covered by the gitsigns sheet with the native list)',
    "A8 with real servers: `lsh`/`lsH` on a Go type that implements an interface shows its sub-/supertypes (gopls); the same keys in a .ts file print the sentence naming gopls, clangd and jdtls",
    'A11 in a Lua file of the config: `lsc` on a function that calls another prints the "scanning" message once, then the fzf-lua window (needs docmap.nvim with opts.callhierarchy = true and lua_ls; the picker with a stub call hierarchy is covered by the terminal spec)',
    "A7 in your terminal and font: the winbar separator looks right between the chips (the characters are covered by the winbar sheet)",
    "gx in a real Neovim 0.12 terminal session: `gx` on an env link opens its target in the external program (vim.ui.open handing over the resolved file is covered by the gx sheet)",
  },
  judge = {},
}
