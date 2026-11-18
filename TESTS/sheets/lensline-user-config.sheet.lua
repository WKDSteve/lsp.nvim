-- lensline.nvim over the LSP pack, measured on the INSTALLED config (`config = "user"`): opening a Lua file of a git
-- repository attaches lua_ls, lensline loads on that `LspAttach` and draws its lenses, and nothing on the way runs
-- git synchronously. lensline's defaults did: `git blame` of the whole file for `last_author` (200-440 ms frozen per
-- opened file) and `git check-ignore` for `exclude_gitignored` (55-70 ms); lsp.integrations.lensline turns both
-- off (task lsp.nvim/lensline-last-author-sync-blame). The sheet records every `vim.fn.system`/`systemlist` call of
-- the child and fails on a git one; `testing perf --sheet lsp.lensline-user-config` shows them with their time.
-- Only where the config is installed: on CI (and without an init.lua) the sheet is a skip. It has no `feature`
-- on purpose: the catalog entry `lsp.lensline` is `perf = "user"`, and a feature sheet's skip is red on CI.
-- The config loads lsp.nvim from where it installs it (E:/repos/lsp.nvim in dev mode), not from this checkout.
return {
  id = "lsp.lensline-user-config",
  title = "lsp.nvim: lensline over the pack on the installed config runs no synchronous git (no blame, no check-ignore)",
  task = "lsp.nvim/lensline-last-author-sync-blame",
  engine = "rpc",
  config = "user",
  sizes = { { rows = 30, cols = 100 } },
  requires = {
    {
      lua = [[vim.fn.isdirectory(vim.fn.stdpath("data") .. "/lazy/lensline.nvim") == 1]],
      reason = "the installed config has no lensline.nvim",
    },
    {
      lua = [[vim.fn.executable("lua-language-server") == 1
        or vim.fn.isdirectory(vim.fn.stdpath("data") .. "/mason/packages/lua-language-server") == 1]],
      reason = "lua-language-server is not installed (PATH or mason)",
    },
  },
  steps = {
    {
      wait = "package.loaded['lazy'] ~= nil",
      timeout = 30000,
      note = "the installed config is up",
    },
    {
      lua = [[_G.sync_calls = {}
      for _, fname in ipairs({ "system", "systemlist" }) do
        local orig = vim.fn[fname]
        vim.fn[fname] = function(cmd, ...)
          local argv = type(cmd) == "table" and table.concat(cmd, " ") or tostring(cmd)
          _G.sync_calls[#_G.sync_calls + 1] = argv
          return orig(cmd, ...)
        end
      end]],
      note = "every synchronous vim.fn.system/systemlist call from here on is recorded",
    },
    { keys = ":edit lua/lsp/init.lua<CR>", note = "open a Lua file of this repository" },
    {
      wait = [[#vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0]],
      timeout = 60000,
      note = "lua_ls attached",
    },
    {
      wait = [[package.loaded["lensline"] ~= nil]],
      timeout = 30000,
      note = "lensline loaded on the attach",
    },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { vim.fn.search("^local function setup_tools", "n"), 0 })
      vim.defer_fn(function() _G.lens_settled = true end, 3000)]],
      note = "the cursor on a function (lenses render for the focused one); give lensline 3 s",
    },
    { wait = "_G.lens_settled == true", timeout = 10000, note = "lensline had its time" },
    {
      expect = [[(function()
        for _, argv in ipairs(_G.sync_calls) do
          if argv:find("git", 1, true) and (argv:find("blame", 1, true) or argv:find("check-ignore", 1, true)) then
            return false
          end
        end
        return true
      end)()]],
      note = "no synchronous git blame or git check-ignore",
    },
  },
  judge = {},
  manual = {
    "with `testing perf --sheet lsp.lensline-user-config`: the git row of lensline has no sync starts",
  },
}
