-- Live check A3 of the lspsaga replacements (task lsp.nvim/live-check-lspsaga-replacements): in Visual mode
-- `l` extends the selection at once, without waiting for 'timeoutlen'. The code action key `lsa` had been
-- mapped in Visual mode too, which made `l` a prefix there (e6d716d); the range key is `gra`, whose prefix
-- `g` is no key anyone types alone. 'timeoutlen' is set to 5 s here, so a prefix would show as a cursor that
-- has not moved after 400 ms.
return {
  id = "lsp.visual-l-no-wait",
  title = "lsp.nvim: l in Visual mode does not wait for timeoutlen",
  task = "lsp.nvim/live-check-lspsaga-replacements",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      vim.o.timeoutlen = 5000
      require("lsp").setup({})
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef", "ghijkl", "mnopqr" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })]],
      note = "lsp.nvim set up (its keymaps are on), a three line buffer, timeoutlen 5000",
    },
    {
      expect = [[vim.fn.maparg("lsa", "n") ~= ""]],
      note = "the Normal-mode code action key is mapped",
    },
    {
      expect = [[vim.fn.mapcheck("l", "x") == ""]],
      note = "no Visual-mode mapping starts with l (mapcheck finds none)",
    },
    {
      expect = [[vim.fn.maparg("gra", "x", false, true).desc:find("Code action", 1, true) ~= nil]],
      note = "the range key gra is the Visual-mode code action",
    },
    { input = "vl", note = "start a selection and extend it with l, without waiting" },
    {
      wait = [[vim.api.nvim_get_mode().mode == "v" and vim.fn.col(".") == 2]],
      timeout = 400,
      note = "the selection grew within 400 ms, far below the 5 s timeoutlen",
    },
    { input = "jl", note = "and j, l after it" },
    {
      wait = [[vim.fn.line(".") == 2 and vim.fn.col(".") == 3]],
      timeout = 400,
      note = "the cursor followed at once",
    },
  },
  judge = {},
  manual = {},
}
