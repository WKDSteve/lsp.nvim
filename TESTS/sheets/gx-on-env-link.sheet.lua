-- Live check: `gx` on an env link (task lsp.nvim/live-check-lspsaga-replacements, the gx point).
-- Automated: in a Markdown buffer the in-process env-link server answers documentLink for
-- `[t]($LSPSHEET_ROOT/target.md)`, and Neovim 0.12's `gx` hands the resolved file to
-- `vim.ui.open` (it also hands over the destination as written, which `vim.fs.normalize` expands to the
-- same file). `vim.ui.open` is stubbed in the child and records its argument, so nothing is
-- opened; a link to a file that is not there gets no entry and `gx` falls back to `<cfile>`.
-- Not covered (stays by hand in the task): the real external program opening the target.
return {
  id = "lsp.gx-env-link",
  title = "lsp.nvim: gx on an env link hands the target to vim.ui.open",
  task = "lsp.nvim/live-check-lspsaga-replacements",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = 'vim.opt.shortmess:append("I"); vim.o.laststatus = 0; vim.o.ruler = false',
      note = "no intro, no status line",
    },
    {
      lua = [[local root = vim.fn.tempname()
      vim.fn.mkdir(root, "p")
      vim.fn.writefile({ "target" }, root .. "/target.md")
      vim.fn.writefile({ "[t]($LSPSHEET_ROOT/target.md)", "[g]($LSPSHEET_ROOT/gone.md)" }, root .. "/note.md")
      vim.env.LSPSHEET_ROOT = root
      _G.sheet_root = vim.fs.normalize(root)
      _G.opened = {}
      vim.ui.open = function(path)
        _G.opened[#_G.opened + 1] = path
        return { wait = function() return { code = 0 } end }, nil
      end
      require("lsp.core.env_links_server").setup({ env_links = true })
      vim.cmd.edit(vim.fn.fnameescape(root .. "/note.md"))]],
      note = "a note with two env links, one to an existing file and one to none; vim.ui.open stubbed",
    },
    {
      wait = [[#vim.lsp.get_clients({ bufnr = 0, name = require("lsp.core.env_links_server").NAME }) > 0]],
      note = "the env-link server is attached to the buffer",
    },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { 1, 6 })]],
      note = "the cursor on the link target of line 1",
    },
    { keys = "gx", note = "follow the link" },
    {
      wait = [[#_G.opened > 0]],
      note = "gx called vim.ui.open",
    },
    {
      expect = [[(function()
        local want, resolved = _G.sheet_root .. "/target.md", false
        for _, item in ipairs(_G.opened) do
          local path = item:find("^file:") and vim.uri_to_fname(item) or item
          if not path:find("$", 1, true) and vim.fs.normalize(path) == want then
            resolved = true
          end
        end
        return resolved
      end)()]],
      note = "one of the calls carries the file the link names, already resolved from $LSPSHEET_ROOT (by the server)",
    },
    {
      expect = [[(function()
        for _, item in ipairs(_G.opened) do
          local path = item:find("^file:") and vim.uri_to_fname(item) or item
          if vim.fs.normalize(path) ~= _G.sheet_root .. "/target.md" then
            return false
          end
        end
        return true
      end)()]],
      note = "and every call (gx also hands over the written destination) leads to that same file",
    },
  },
  judge = {},
  manual = {
    "in a real terminal session gx on an env link opens the target in the external program",
  },
}
