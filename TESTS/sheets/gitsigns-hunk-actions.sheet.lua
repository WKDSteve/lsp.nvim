-- Live checks A4 and A9 of the lspsaga replacements (task lsp.nvim/live-check-lspsaga-replacements) against the
-- REAL gitsigns in a real git repository: the hunk actions are offered in the code action list (`lsa` at the
-- cursor, `gra` for a selection), also on a deleted line at the start and at the end of the file, and
-- "Stage hunk" stages what the check names (`git diff --cached`): both hunks of a selection, the whole hunk
-- when the cursor is in a multi-line one. The code action list is the native one (`vim.ui.select` is
-- recorded and answers), the fzf window of `lsa` has its own terminal spec (TESTS/lsp/pty_fzf_spec.lua).
-- n/a without gitsigns.nvim (or git) on the machine.
-- the lazy directory of the real user (the child's own stdpath is a sandbox): Windows or XDG
local LAZY =
  '(vim.env.LOCALAPPDATA and (vim.env.LOCALAPPDATA .. "/nvim-data/lazy/") or ((vim.env.HOME or "") .. "/.local/share/nvim/lazy/"))'
local FIND = "vim.fn.isdirectory(" .. LAZY .. ' .. "gitsigns.nvim") == 1'
return {
  id = "lsp.gitsigns-hunk-actions",
  title = "lsp.nvim: gitsigns hunk actions in lsa/gra stage the right hunks (real gitsigns)",
  task = "lsp.nvim/live-check-lspsaga-replacements",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  requires = {
    {
      lua = FIND .. ' and vim.fn.executable("git") == 1',
      reason = "gitsigns.nvim (in the lazy directory of this user) or git is not installed here",
    },
  },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      local lazy = vim.env.LOCALAPPDATA and (vim.env.LOCALAPPDATA .. "/nvim-data/lazy/") or ((vim.env.HOME or "") .. "/.local/share/nvim/lazy/")
      for _, n in ipairs({ "plenary.nvim", "gitsigns.nvim" }) do vim.opt.rtp:append(lazy .. n) end
      for _, d in ipairs({ "data", "state", "cache" }) do vim.fn.mkdir(vim.fn.stdpath(d), "p") end
      local root = vim.fs.normalize(vim.fn.tempname()) .. "-repo"
      vim.fn.mkdir(root, "p")
      _G.root = root
      _G.git = function(...)
        local r = vim.system({ "git", "-C", root, "-c", "user.email=t@t", "-c", "user.name=t", ... }, { text = true }):wait()
        assert(r.code == 0, r.stderr)
        return r.stdout
      end
      _G.git("init", "-q")
      local function twelve() local t = {} for i = 1, 12 do t[i] = "line " .. i end return t end
      for _, name in ipairs({ "f.txt", "g.txt", "h.txt", "i.txt" }) do
        vim.fn.writefile(twelve(), root .. "/" .. name)
      end
      _G.git("add", ".")
      _G.git("commit", "-q", "-m", "init")
      -- f: two one-line hunks; g: one three-line hunk; h: first line deleted; i: last line deleted
      local f, g, h, i = twelve(), twelve(), twelve(), twelve()
      f[3], f[9] = "CHANGED 3", "CHANGED 9"
      g[5], g[6], g[7] = "CHANGED 5", "CHANGED 6", "CHANGED 7"
      table.remove(h, 1)
      table.remove(i, 12)
      vim.fn.writefile(f, root .. "/f.txt")
      vim.fn.writefile(g, root .. "/g.txt")
      vim.fn.writefile(h, root .. "/h.txt")
      vim.fn.writefile(i, root .. "/i.txt")
      require("lsp").setup({ code_actions = { gitsigns = true, picker = "native" } })
      require("gitsigns").setup({})
      -- the code action list: record the titles and answer with the one that contains _G.want
      _G.titles, _G.want = {}, nil
      vim.ui.select = function(items, opts, on_choice)
        _G.titles = {}
        local pick
        for _, item in ipairs(items) do
          local title = opts.format_item and opts.format_item(item) or tostring(item)
          _G.titles[#_G.titles + 1] = title
          if _G.want and title:find(_G.want, 1, true) then pick = pick or item end
        end
        on_choice(pick)
      end
      -- open a file and wait for gitsigns to know its hunks
      _G.open = function(name, hunks)
        vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. name))
        return vim.wait(8000, function()
          return #vim.lsp.get_clients({ bufnr = 0, name = "lsp.nvim-gitsigns" }) > 0 and #(require("gitsigns").get_hunks() or {}) == hunks
            -- lsp.nvim caches the hunk spans per GitSignsUpdate: ask only once its cache knows a hunk
            and require("lsp.core.gitsigns_actions").touches_hunk(vim.api.nvim_get_current_buf(), 0, vim.api.nvim_buf_line_count(0) - 1)
        end, 50)
      end
      _G.staged = function(name) return _G.git("diff", "--cached", "--", name) end]],
      note = "a git repo with four tracked files and local changes; real gitsigns; lsp.nvim with the hunk actions on; the native list recorded",
    },

    {
      expect = [[_G.open("f.txt", 2)]],
      note = "f.txt: gitsigns sees two hunks and the hunk client is attached",
    },
    {
      lua = [[_G.want = "Stage hunk"; vim.api.nvim_win_set_cursor(0, { 3, 0 })]],
      note = "cursor on the first changed line",
    },
    { keys = "lsa", note = "lsa at the cursor" },
    {
      wait = [[vim.tbl_contains(_G.titles, "gitsigns: Stage hunk") and vim.tbl_contains(_G.titles, "gitsigns: Reset hunk") and vim.tbl_contains(_G.titles, "gitsigns: Preview hunk")]],
      timeout = 8000,
      note = "A4: the list offers Stage, Reset and Preview hunk",
    },
    {
      wait = [[_G.staged("f.txt"):find("CHANGED 3", 1, true) ~= nil]],
      timeout = 5000,
      note = "A4: Stage hunk stages the hunk for real",
    },
    {
      expect = [[_G.staged("f.txt"):find("CHANGED 9", 1, true) == nil]],
      note = "and only that one",
    },
    { lua = [[_G.git("reset", "-q"); vim.cmd("edit!")]], note = "unstage again" },
    {
      expect = [[vim.wait(8000, function() return #(require("gitsigns").get_hunks() or {}) == 2 end, 50)]],
      note = "gitsigns sees two hunks again",
    },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { 3, 0 })
      vim.cmd("normal! V6j")]],
      note = "A9: select from line 3 to line 9 (both hunks and the lines between)",
    },
    { keys = "gra", note = "gra over the selection" },
    {
      wait = [[(function() local d = _G.staged("f.txt") return d:find("CHANGED 3", 1, true) ~= nil and d:find("CHANGED 9", 1, true) ~= nil end)()]],
      timeout = 5000,
      note = "A9: both hunks of the selection are staged",
    },

    { expect = [[_G.open("g.txt", 1)]], note = "g.txt: one three-line hunk" },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { 6, 0 })]],
      note = "cursor on the MIDDLE line of the hunk",
    },
    { keys = "lsa" },
    {
      wait = [[(function() local d = _G.staged("g.txt") return d:find("CHANGED 5", 1, true) ~= nil and d:find("CHANGED 6", 1, true) ~= nil and d:find("CHANGED 7", 1, true) ~= nil end)()]],
      timeout = 5000,
      note = "A9: from a line inside a multi-line hunk the whole hunk is staged",
    },

    { expect = [[_G.open("h.txt", 1)]], note = "h.txt: the first line is deleted" },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { 1, 0 })]],
      note = "cursor on the first line of the file",
    },
    { keys = "lsa" },
    {
      wait = [[vim.tbl_contains(_G.titles, "gitsigns: Stage hunk")]],
      timeout = 8000,
      note = "A4: a deleted line at the start of the file still offers the hunk actions",
    },
    {
      wait = [[_G.staged("h.txt"):find("-line 1", 1, true) ~= nil]],
      timeout = 5000,
      note = "A4: and Stage hunk stages that deletion",
    },

    { expect = [[_G.open("i.txt", 1)]], note = "i.txt: the last line is deleted" },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })]],
      note = "cursor on the last line of the file",
    },
    { keys = "lsa" },
    {
      wait = [[vim.tbl_contains(_G.titles, "gitsigns: Stage hunk")]],
      timeout = 8000,
      note = "A4: a deleted line at the end of the file still offers the hunk actions",
    },
    {
      wait = [[_G.staged("i.txt"):find("-line 12", 1, true) ~= nil]],
      timeout = 5000,
      note = "A4: and Stage hunk stages that deletion",
    },
  },
  judge = {},
  manual = {},
}
