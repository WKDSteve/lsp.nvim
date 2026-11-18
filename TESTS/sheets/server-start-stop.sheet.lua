-- Feature sheet for the server start (catalog `lsp.servers`): opening a file starts its language server as a real
-- process, the client attaches with lsp.nvim's hooks (the winbar names the symbol the server reports), and
-- `:LspStopHere` ends the process again. The server is TESTS/support/stdio_server.lua run by the editor itself
-- (`nvim -l`) for a filetype none of lsp.nvim's own servers claim, so the sheet needs no language server on the
-- machine and runs on CI. `testing perf` measures the start, the size of the server process and that nothing of it
-- is left after the stop.
return {
  id = "lsp.server-start-stop",
  feature = "lsp.servers",
  title = "lsp.nvim: opening a file starts its server as a process, :LspStopHere ends it",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      local root = vim.fs.normalize(vim.fn.tempname())
      vim.fn.mkdir(root, "p")
      -- the physical path: on macOS the temp folder is a symlink, and getcwd() and the tools report the real one
      root = vim.fs.normalize(vim.uv.fs_realpath(root))
      _G.root = root
      vim.fn.writefile({ "stdio_symbol = 1", "" }, root .. "/main.stdioft")
      vim.fn.writefile({}, root .. "/.stdio-root")
      vim.filetype.add({ extension = { stdioft = "stdioft" } })
      require("lsp").setup({})
      local server = vim.fn.getcwd() .. "/TESTS/support/stdio_server.lua"
      vim.lsp.config("stdio_server", {
        cmd = { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", server },
        filetypes = { "stdioft" },
        root_markers = { ".stdio-root" },
      })
      vim.lsp.enable("stdio_server")
      vim.cmd.cd(vim.fn.fnameescape(root))]],
      note = "a project with one file (the working directory); the stdio server is configured for its filetype",
    },
    { keys = ":edit main.stdioft<CR>", note = "open the file" },
    {
      wait = [[(function()
        local c = vim.lsp.get_clients({ bufnr = 0, name = "stdio_server" })[1]
        return c ~= nil and c.initialized == true
      end)()]],
      timeout = 10000,
      note = "the server process started and the client is initialized",
    },
    {
      expect = [[(function()
        local c = vim.lsp.get_clients({ bufnr = 0, name = "stdio_server" })[1]
        return vim.fs.normalize(c.root_dir) == _G.root
      end)()]],
      note = "its root is the project (the marker file)",
    },
    {
      wait = [[vim.wo.winbar:find("stdio_symbol", 1, true) ~= nil]],
      timeout = 8000,
      note = "the winbar shows the symbol the server reported (lsp.nvim's attach hooks ran)",
    },
    { keys = ":LspStopHere<CR>", note = "stop the servers of the buffer" },
    {
      wait = [[#vim.lsp.get_clients({ name = "stdio_server" }) == 0]],
      timeout = 8000,
      note = "the client is gone",
    },
    {
      expect = [[vim.fn.execute("messages"):find("Stopped 1 LSP client(s)", 1, true) ~= nil]],
      note = "it says one server was stopped",
    },
  },
  judge = {},
  manual = {
    "the same with your own servers on a real project: `:Lsp servers` names them, and after :LspStopHere the process list (Task Manager, `ps`) has no lua-language-server / tsserver of that project left",
  },
}
