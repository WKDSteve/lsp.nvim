-- Live check of `:Lsp help` (task lsp.nvim/deprecated-help-word-under-cursor) in a real child editor: the
-- key configured as `keymaps.map.word_help` on `fs_stat` in Lua code finds `*uv.fs_stat()*` through the help page `luvref` named for the
-- filetype and shows it in a float, the focus stays in the code; a word without help ends in a message and opens
-- nothing; with `display = "help"` the same key jumps into luvref.txt at the tag. No server is needed: the lookup
-- reads help files, not LSP answers.
return {
  id = "lsp.help-word-under-cursor",
  feature = "lsp.help-word",
  title = "lsp.nvim: the help of the word under the cursor, from the filetype's help page, in a float or jumped to",
  task = "lsp.nvim/deprecated-help-word-under-cursor",
  engine = "rpc",
  sizes = { { rows = 30, cols = 100 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      vim.g.mapleader = " "
      _G.notes = {}
      local real = vim.notify
      vim.notify = function(msg, level, opts)
        _G.notes[#_G.notes + 1] = tostring(msg)
        return real(msg, level, opts)
      end
      require("lsp").setup({
        keymaps = { map = { word_help = "<leader>K" } },
        tools = { deprecated_help = { help_pages = { lua = { "luvref" } } } },
      })
      vim.bo.filetype = "lua"
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local st = vim.uv.fs_stat(path)" })
      vim.api.nvim_win_set_cursor(0, { 1, 20 })
      _G.code_win = vim.api.nvim_get_current_win()
      _G.float = function()
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(w).relative ~= "" then return w end
        end
      end]],
      note = "a Lua buffer `local st = vim.uv.fs_stat(path)`, the cursor on fs_stat; key <leader>K, page luvref for lua",
    },
    { expect = [[vim.fn.maparg("<leader>K", "n") ~= ""]], note = "the configured key is bound" },
    { keys = " K", note = "ask for the help of the word under the cursor" },
    {
      wait = [[_G.float() ~= nil]],
      note = "a float opens",
    },
    {
      expect = [[vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(_G.float()), 0, 1, false)[1]:find("*uv.fs_stat()*", 1, true) ~= nil]],
      note = "it shows the luvref entry of uv.fs_stat()",
    },
    {
      expect = [[vim.api.nvim_get_current_win() == _G.code_win]],
      note = "the focus stays in the code",
    },
    {
      lua = [[pcall(vim.api.nvim_win_close, _G.float(), true); _G.notes = {}]],
      note = "close the float",
    },
    { keys = ":Lsp help zzqx_no_such_help_word<CR>", note = "a word that has no help" },
    {
      wait = [[#_G.notes > 0]],
      note = "a message comes",
    },
    {
      expect = [[_G.notes[1]:find("No help found for: zzqx_no_such_help_word", 1, true) ~= nil and _G.float() == nil]],
      note = "it says nothing was found, and no float opened",
    },
    {
      lua = [[require("lsp.tools.deprecated_help.defaults").display = "help"]],
      note = 'display = "help"',
    },
    { keys = " K", note = "the same key again" },
    {
      wait = [[vim.bo.buftype == "help"]],
      note = "a help window opens",
    },
    {
      expect = [[vim.fn.expand("%:t") == "luvref.txt" and vim.api.nvim_get_current_line():find("*uv.fs_stat()*", 1, true) ~= nil]],
      note = "it is luvref.txt, the cursor on the line of the tag",
    },
  },
  judge = {},
  manual = {},
}
