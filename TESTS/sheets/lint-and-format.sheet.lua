-- Feature sheet for the ESLint/Prettier tools (catalog `lsp.extras`): in a TypeScript project with an eslint and a
-- prettier config, `:LintAndFormat` runs `eslint_d --fix <file>` and, after it has exited, `prettier --write
-- <file>`, both from the project root. eslint_d and prettier are stand-ins (`fakes`): the sheet proves what is run,
-- in which order and where, not what the tools do to the file; `testing perf` measures the two starts.
return {
  id = "lsp.lint-and-format",
  feature = "lsp.extras",
  title = "lsp.nvim: :LintAndFormat runs eslint_d --fix, then prettier --write, from the project root",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  fakes = { "eslint_d", "prettier" },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      -- room for the two reports, so that they need no hit-enter prompt
      vim.o.cmdheight = 3
      local root = vim.fs.normalize(vim.fn.tempname())
      vim.fn.mkdir(root .. "/src", "p")
      -- the physical path: on macOS the temp folder is a symlink, and getcwd() and the tools report the real one
      root = vim.fs.normalize(vim.uv.fs_realpath(root))
      _G.root = root
      vim.fn.writefile({ "export default [];" }, root .. "/eslint.config.js")
      vim.fn.writefile({ "{}" }, root .. "/.prettierrc")
      vim.fn.writefile({ "const a = 1" }, root .. "/src/app.ts")
      require("lsp").setup({ servers = { "lua_ls" } })
      vim.cmd.cd(vim.fn.fnameescape(root))]],
      note = "a TypeScript project with eslint.config.js and .prettierrc; a user with lua_ls only (no ts_ls of the machine starts)",
    },
    { keys = ":edit src/app.ts<CR>", note = "open a source file" },
    { keys = ":LintAndFormat<CR>", note = "lint and format it" },
    {
      wait = [[#require("testing.fake_programs").read(vim.env.TESTING_FAKES, "prettier") == 1]],
      timeout = 8000,
      note = "prettier ran",
    },
    {
      wait = [[vim.fn.execute("messages"):find("prettier: formatted", 1, true) ~= nil]],
      timeout = 8000,
      note = "it says so",
    },
    {
      expect = [[vim.fn.execute("messages"):find("eslint_d: fixed", 1, true) ~= nil]],
      note = "and eslint_d said it fixed the file",
    },
    {
      expect = [[(function()
        local calls = require("testing.fake_programs").read(vim.env.TESTING_FAKES)
        return #calls == 2 and calls[1].program == "eslint_d" and calls[2].program == "prettier"
      end)()]],
      note = "eslint_d first, prettier after it, each once",
    },
    {
      expect = [[(function()
        local e = require("testing.fake_programs").read(vim.env.TESTING_FAKES, "eslint_d")[1]
        return e.argv[1] == "--fix" and vim.fs.normalize(e.argv[2]) == _G.root .. "/src/app.ts"
          and vim.fs.normalize(e.cwd) == _G.root
      end)()]],
      note = "eslint_d --fix on the file, from the project root",
    },
    {
      expect = [[(function()
        local p = require("testing.fake_programs").read(vim.env.TESTING_FAKES, "prettier")[1]
        return vim.tbl_contains(p.argv, "--write") and vim.fs.normalize(p.argv[#p.argv]) == _G.root .. "/src/app.ts"
          and vim.fs.normalize(p.cwd) == _G.root
      end)()]],
      note = "prettier --write on the file, from the project root",
    },
  },
  judge = {},
  manual = {
    "once with the real eslint_d and prettier on a project: the file is fixed and formatted, and both changes are in the buffer after the command",
  },
}
