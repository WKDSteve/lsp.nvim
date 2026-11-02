-- Live check A5 of the lspsaga replacements (task lsp.nvim/live-check-lspsaga-replacements): the buffer a
-- peek float shows is taken over with <C-o> / <C-v> / <C-x> / <C-t>, and then it is LISTED (`:ls`, tabline,
-- buffer pickers). A stub server answers `textDocument/definition` with a file that is not open. While the
-- peek is open the buffer is unlisted (it is unloaded again when the peek closes).
return {
  id = "lsp.peek-take-over",
  title = "lsp.nvim: a peeked buffer taken over with <C-o>, <C-v>, <C-x> or <C-t> is listed",
  task = "lsp.nvim/live-check-lspsaga-replacements",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      local root = vim.fn.tempname()
      vim.fn.mkdir(root, "p")
      vim.fn.writefile({ "call_it()", "" }, root .. "/main.stubft")
      vim.fn.writefile({ "-- header", "function call_it()", "  return 1", "end" }, root .. "/other.stubft")
      require("lsp").setup({})
      local S = dofile(vim.fn.getcwd() .. "/TESTS/support/stub_server.lua")
      _G.main, _G.other = root .. "/main.stubft", root .. "/other.stubft"
      vim.cmd.edit(vim.fn.fnameescape(_G.main))
      vim.bo.filetype = "stubft"
      local target = vim.uri_from_fname(_G.other)
      S.start({
        name = "stubdef", bufnr = 0, root = root, capabilities = { definitionProvider = true },
        handlers = { ["textDocument/definition"] = function()
          return { { uri = target, range = S.range(1, 9, 16) } }
        end },
      })
      -- back to a clean start for each variant, and a way to ask about the buffer of other.stubft
      _G.reset = function()
        vim.cmd("silent! tabonly | silent! only")
        vim.cmd.edit(vim.fn.fnameescape(_G.main))
        local nr = vim.fn.bufnr(_G.other)
        if nr > 0 then vim.cmd("silent! bwipeout! " .. nr) end
      end
      _G.other_buf = function()
        local nr = vim.fn.bufnr(_G.other)
        return nr > 0 and vim.api.nvim_buf_is_valid(nr) and nr or nil
      end]],
      note = "a buffer with a stub definition server; main.stubft and other.stubft in a temp folder",
    },
    {
      wait = [[#vim.lsp.get_clients({ bufnr = 0, name = "stubdef" }) > 0]],
      note = "the stub server is attached",
    },

    { keys = "lsp", note = "peek the definition" },
    {
      wait = [[vim.api.nvim_win_get_config(0).relative ~= "" and vim.fn.expand("%:t") == "other.stubft"]],
      note = "a float opened over the code, showing other.stubft",
    },
    { expect = [[not vim.bo.buflisted]], note = "while peeked, the buffer is not listed" },
    { keys = "<C-o>", note = "take it into the window we came from" },
    {
      expect = [[vim.api.nvim_win_get_config(0).relative == "" and vim.fn.expand("%:t") == "other.stubft"]],
      note = "<C-o>: the window shows it",
    },
    {
      expect = [[vim.bo.buflisted and vim.fn.execute("ls"):find("other.stubft", 1, true) ~= nil]],
      note = "<C-o>: :ls lists it",
    },

    { lua = [[_G.reset()]], note = "start over" },
    { keys = "lsp" },
    {
      wait = [[vim.api.nvim_win_get_config(0).relative ~= "" and vim.fn.expand("%:t") == "other.stubft"]],
    },
    { keys = "<C-v>", note = "take it into a vertical split" },
    {
      expect = [[#vim.api.nvim_tabpage_list_wins(0) == 2 and vim.fn.expand("%:t") == "other.stubft" and vim.api.nvim_win_get_config(0).relative == ""]],
      note = "<C-v>: two windows side by side, the new one shows it",
    },
    {
      expect = [[vim.bo.buflisted and vim.fn.execute("ls"):find("other.stubft", 1, true) ~= nil]],
      note = "<C-v>: :ls lists it",
    },

    { lua = [[_G.reset()]], note = "start over" },
    { keys = "lsp" },
    {
      wait = [[vim.api.nvim_win_get_config(0).relative ~= "" and vim.fn.expand("%:t") == "other.stubft"]],
    },
    { keys = "<C-x>", note = "take it into a horizontal split" },
    {
      expect = [[#vim.api.nvim_tabpage_list_wins(0) == 2 and vim.fn.expand("%:t") == "other.stubft" and vim.api.nvim_win_get_config(0).relative == ""]],
      note = "<C-x>: two windows, the new one shows it",
    },
    {
      expect = [[vim.bo.buflisted and vim.fn.execute("ls"):find("other.stubft", 1, true) ~= nil]],
      note = "<C-x>: :ls lists it",
    },

    { lua = [[_G.reset()]], note = "start over" },
    { keys = "lsp" },
    {
      wait = [[vim.api.nvim_win_get_config(0).relative ~= "" and vim.fn.expand("%:t") == "other.stubft"]],
    },
    { keys = "<C-t>", note = "take it into a new tab" },
    {
      expect = [[#vim.api.nvim_list_tabpages() == 2 and vim.fn.expand("%:t") == "other.stubft"]],
      note = "<C-t>: a second tab shows it",
    },
    {
      expect = [[vim.bo.buflisted and vim.fn.execute("ls"):find("other.stubft", 1, true) ~= nil]],
      note = "<C-t>: :ls lists it",
    },

    { lua = [[_G.reset()]], note = "start over" },
    { keys = "lsp" },
    {
      wait = [[vim.api.nvim_win_get_config(0).relative ~= "" and vim.fn.expand("%:t") == "other.stubft"]],
    },
    { keys = "q", note = "close the peek without taking the buffer" },
    {
      expect = [[vim.fn.expand("%:t") == "main.stubft" and (not _G.other_buf() or not vim.api.nvim_buf_is_loaded(_G.other_buf()))]],
      note = "q: back in the code, and the peeked buffer is unloaded again, not left in the list",
    },
  },
  judge = {},
  manual = {},
}
