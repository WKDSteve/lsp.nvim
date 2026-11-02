-- Live check A7 of the lspsaga replacements (task lsp.nvim/live-check-lspsaga-replacements): the winbar
-- separator `›` renders cleanly between the chips, not as mojibake (a double-encoded form). A stub server answers
-- documentSymbol for a Lua module, so the breadcrumb has folder, file and function chips. The folder is
-- named `proj`, the rest of the screen is masked; the one row left in the snapshot is the winbar.
-- What stays by hand: the glyphs in the font of the real terminal (the snapshot is characters, not pixels).
return {
  id = "lsp.winbar-separator",
  title = "lsp.nvim: the winbar separator is the single character U+203A between clean chips",
  task = "lsp.nvim/live-check-lspsaga-replacements",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0; vim.o.ruler = false
      local root = vim.fn.tempname() .. "/proj"
      vim.fn.mkdir(root, "p")
      vim.fn.writefile({ "local M = {}", "function M.total(a, b)", "  return a + b", "end", "return M" }, root .. "/mod.lua")
      require("lsp").setup({})
      vim.cmd.edit(vim.fn.fnameescape(root .. "/mod.lua"))
      local S = dofile(vim.fn.getcwd() .. "/TESTS/support/stub_server.lua")
      S.start({
        name = "stublua", bufnr = 0, root = root, capabilities = { documentSymbolProvider = true },
        handlers = { ["textDocument/documentSymbol"] = function()
          return { { name = "total", kind = 12, selectionRange = S.range(1, 9, 14),
            range = { start = { line = 1, character = 0 }, ["end"] = { line = 3, character = 3 } } } }
        end },
      })
      vim.api.nvim_win_set_cursor(0, { 3, 4 })]],
      note = "a Lua module in a folder called proj, a stub server with one function symbol, the cursor inside it",
    },
    {
      wait = [[vim.api.nvim_eval_statusline(vim.wo.winbar, { winid = 0, use_winbar = true }).str:find("total", 1, true) ~= nil]],
      timeout = 5000,
      note = "the breadcrumb reached the function chip",
    },
    {
      expect = [[vim.api.nvim_eval_statusline(vim.wo.winbar, { winid = 0, use_winbar = true }).str:find("\226\128\186", 1, true) ~= nil]],
      note = "the separator is the three UTF-8 bytes of U+203A",
    },
    {
      expect = [[vim.api.nvim_eval_statusline(vim.wo.winbar, { winid = 0, use_winbar = true }).str:find("\195\162", 1, true) == nil]],
      note = "and no double-encoded form (a stray U+00E2 would be the first byte of the mojibake)",
    },
    {
      screen = "winbar",
      masks = { { row = 2, col = 1, cols = 80, rows = 23 } },
      cursor = false,
      mode = false,
      note = "row 1 of the screen is the breadcrumb: proj, mod.lua, total",
    },
  },
  judge = {},
  manual = {
    "in the real terminal and font of your setup the separator looks right between the chips (no replacement glyph, spacing)",
  },
}
