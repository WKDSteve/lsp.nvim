-- Feature sheet for the Astro commands (catalog `lsp.astro-commands`): in an Astro project, `:AstroDevStop` ends
-- the dev server with `pkill -f "astro dev"` and `:AstroBuild` runs `astro build` and shows what it printed. astro
-- and pkill are stand-ins (`fakes`), so nothing is built or killed; `testing perf` measures the two starts, and
-- both wait for their process (`vim.system():wait()`): the editor is blocked for as long as the build runs.
return {
  id = "lsp.astro-build-stop",
  feature = "lsp.astro-commands",
  title = "lsp.nvim: :AstroDevStop runs pkill -f 'astro dev', :AstroBuild runs astro build and shows its output",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  fakes = { "astro", "pkill" },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      vim.o.cmdheight = 2
      local root = vim.fs.normalize(vim.fn.tempname())
      vim.fn.mkdir(root .. "/src/pages", "p")
      -- the physical path: on macOS the temp folder is a symlink, and getcwd() and the tools report the real one
      root = vim.fs.normalize(vim.uv.fs_realpath(root))
      vim.fn.writefile({ "export default {};" }, root .. "/astro.config.mjs")
      vim.fn.writefile({ "---", "---", "<h1>Hi</h1>" }, root .. "/src/pages/index.astro")
      require("lsp").setup({ servers = { "lua_ls" } })
      vim.cmd.cd(vim.fn.fnameescape(root))]],
      note = "an Astro project (the working directory); a user with lua_ls only",
    },
    { keys = ":edit src/pages/index.astro<CR>", note = "open a page" },
    { keys = ":AstroDevStop<CR>", note = "stop the dev server" },
    {
      wait = [[vim.fn.execute("messages"):find("Astro dev server stopped", 1, true) ~= nil]],
      timeout = 8000,
      note = "it says the dev server is stopped",
    },
    {
      expect = [[(function()
        local calls = require("testing.fake_programs").read(vim.env.TESTING_FAKES, "pkill")
        return #calls == 1 and calls[1].argv[1] == "-f" and calls[1].argv[2] == "astro dev"
      end)()]],
      note = "pkill -f 'astro dev' ran once",
    },
    { keys = ":AstroBuild<CR>", note = "build the project" },
    {
      wait = [[#require("testing.fake_programs").read(vim.env.TESTING_FAKES, "astro") == 1]],
      timeout = 8000,
      note = "astro ran",
    },
    {
      expect = [[(function()
        local call = require("testing.fake_programs").read(vim.env.TESTING_FAKES, "astro")[1]
        return call.argv[1] == "build" and vim.fs.normalize(call.cwd) == vim.fs.normalize(vim.fn.getcwd())
      end)()]],
      note = "astro build, in the project",
    },
    {
      expect = [[not vim.fn.execute("messages"):find("astro build exited", 1, true)]],
      note = "the build exited 0: no warning",
    },
  },
  judge = {},
  manual = {
    "once with the real astro on an Astro project: :AstroBuild shows the build's output when it is done (the editor waits for it)",
  },
}
