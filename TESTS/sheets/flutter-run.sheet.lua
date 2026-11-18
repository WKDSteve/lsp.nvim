-- Feature sheet for `flutter run` (catalog `lsp.flutter-run`): in a Dart file of a Flutter project, `<leader>fr`
-- opens a terminal split below that runs `flutter run` from the project root (the folder of pubspec.yaml, not the
-- editor's working directory). flutter is a stand-in (`fakes`) that ends at once: nothing is built or launched, and
-- that a second press focuses a run that is still up stays a spec (TESTS/lsp/languages_spec.lua) and a hand check;
-- `testing perf` measures the start.
return {
  id = "lsp.flutter-run",
  feature = "lsp.flutter-run",
  title = "lsp.nvim: <leader>fr runs flutter run in a terminal split from the project root",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  fakes = { "flutter" },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      vim.o.cmdheight = 2
      vim.g.mapleader = "\\"
      local root = vim.fs.normalize(vim.fn.tempname())
      vim.fn.mkdir(root .. "/app/lib", "p")
      -- the physical path: on macOS the temp folder is a symlink, and getcwd() and the tools report the real one
      root = vim.fs.normalize(vim.uv.fs_realpath(root))
      _G.app = root .. "/app"
      vim.fn.writefile({ "name: app" }, root .. "/app/pubspec.yaml")
      vim.fn.writefile({ "void main() {}" }, root .. "/app/lib/main.dart")
      require("lsp").setup({ servers = { "lua_ls" } })
      vim.cmd.cd(vim.fn.fnameescape(root))]],
      note = "a Flutter project in app/ below the working directory; a user with lua_ls only",
    },
    { keys = ":edit app/lib/main.dart<CR>", note = "open its main.dart" },
    { keys = "\\fr", note = "flutter run" },
    {
      wait = [[#require("testing.fake_programs").read(vim.env.TESTING_FAKES, "flutter") == 1]],
      timeout = 8000,
      note = "flutter ran",
    },
    {
      expect = [[(function()
        local call = require("testing.fake_programs").read(vim.env.TESTING_FAKES, "flutter")[1]
        return call.argv[1] == "run" and vim.fs.normalize(call.cwd) == _G.app
      end)()]],
      note = "flutter run, from the project root (app/), not the working directory",
    },
    {
      expect = [[#vim.api.nvim_list_wins() == 2 and vim.bo.buftype == "terminal"]],
      note = "a terminal split, focused",
    },
    { lua = [[_G.chan = vim.bo.channel]], note = "remember the terminal's job" },
    { keys = ":bdelete!<CR>", note = "close the terminal" },
    {
      wait = [[vim.fn.jobwait({ _G.chan }, 0)[1] ~= -1]],
      timeout = 8000,
      note = "its job has ended: closing the terminal ends the run",
    },
  },
  judge = {},
  manual = {
    "once with the real flutter SDK and a device or emulator: the app starts, `r` in the terminal hot-reloads, and a second <leader>fr while it runs focuses that terminal",
  },
}
