-- Live check A10 of the lspsaga replacements (task lsp.nvim/live-check-lspsaga-replacements):
-- `:LspRestartHere` and `:LspStopHere` on a text file (no servers: a sentence, no winbar) and on a buffer with
-- two real servers and one lsp.nvim in-process client (the counts name the real servers only, the winbar
-- stays). The servers are in-process stubs registered with `vim.lsp.config`, so the check needs no
-- language server on the machine (the filetype `stubft` has none of lsp.nvim's own).
return {
  id = "lsp.restart-stop-here",
  title = "lsp.nvim: :LspRestartHere / :LspStopHere count real servers only, no winbar on a text file",
  task = "lsp.nvim/live-check-lspsaga-replacements",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      local root = vim.fn.tempname()
      vim.fn.mkdir(root, "p")
      _G.root = root
      vim.fn.writefile({ "plain" }, root .. "/note.txt")
      vim.fn.writefile({ "x" }, root .. "/mod.stubft")
      require("lsp").setup({})
      _G.S = dofile(vim.fn.getcwd() .. "/TESTS/support/stub_server.lua")
      for _, n in ipairs({ "stub_one", "stub_two" }) do
        vim.lsp.config(n, { cmd = _G.S.cmd({ name = n, capabilities = { documentSymbolProvider = true } }), filetypes = { "stubft" }, root_markers = { "mod.stubft" } })
      end
      vim.cmd.edit(vim.fn.fnameescape(root .. "/note.txt"))]],
      note = "a text file open; two stub servers registered for the filetype stubft",
    },
    { keys = ":LspRestartHere<CR>", note = "restart on the text file" },
    {
      expect = [[vim.fn.execute("messages"):find("No LSP clients to restart", 1, true) ~= nil]],
      note = "it says there is nothing to restart",
    },
    { keys = ":LspStopHere<CR>", note = "stop on the text file" },
    {
      expect = [[vim.fn.execute("messages"):find("No LSP clients running", 1, true) ~= nil]],
      note = "it says nothing is running",
    },
    { expect = [[vim.wo.winbar == ""]], note = "no winbar on the text file" },
    {
      lua = [[vim.cmd.edit(vim.fn.fnameescape(_G.root .. "/mod.stubft"))
      vim.bo.filetype = "stubft"
      for _, n in ipairs({ "stub_one", "stub_two" }) do require("lsp.core.supervisor").start(n, 0) end
      -- lsp.nvim's own in-process client (like the gitsigns one) must not be counted
      _G.S.start({ name = "lsp.nvim-internal", bufnr = 0, root = _G.root, capabilities = {} })]],
      note = "a stubft buffer with the two stub servers and one lsp.nvim in-process client",
    },
    {
      wait = [[#vim.lsp.get_clients({ bufnr = 0 }) == 3]],
      timeout = 5000,
      note = "three clients are attached",
    },
    {
      lua = [[vim.cmd("messages clear")
      vim.cmd("LspRestartHere")]],
      note = "restart them all",
    },
    {
      wait = [[vim.fn.execute("messages"):find("Restarted 2/2", 1, true) ~= nil]],
      timeout = 8000,
      note = "the message counts 2 of 2 real servers (not 3)",
    },
    {
      wait = [[#vim.lsp.get_clients({ bufnr = 0 }) == 3]],
      timeout = 5000,
      note = "the two servers are back and the in-process client was left alone",
    },
    {
      expect = [[vim.wo.winbar ~= ""]],
      note = "the winbar stays on the buffer with servers",
    },
    {
      lua = [[vim.cmd("messages clear")
      vim.cmd("LspStopHere")]],
      note = "stop them all",
    },
    {
      expect = [[vim.fn.execute("messages"):find("Stopped 2 LSP client(s)", 1, true) ~= nil]],
      note = "two real servers stopped",
    },
  },
  judge = {},
  manual = {
    "the same on a real .txt and a real Lua file of a git repository with your own servers installed (lua_ls, ts_ls): N/N is the number of servers you see in :Lsp servers",
  },
}
