--- `:Lsp help` / `deprecated_help.word`: the help of the word under the
--- cursor, through the float of `help_float`, with per-filetype help pages
--- searched first.

local tracker = dofile(vim.fn.getcwd() .. "/TESTS/support/scratch.lua")

local MODS = {
  "lsp.tools.deprecated_help",
  "lsp.tools.deprecated_help.defaults",
  "lsp.tools.deprecated_help.help_float",
  "lsp.tools.deprecated_help.word",
  "lsp.tools.deprecated_help.lsp.lua_ls.lua_ls",
}

---@return integer[]
local function floats()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      out[#out + 1] = win
    end
  end
  return out
end

--- A help-formatted page on disk, outside the runtimepath.
---@param lines string[]
---@param name? string file name (default: a temp name)
---@return string path
local function page(lines, name)
  local path = vim.fs.normalize(vim.fn.tempname() .. (name or ".txt"))
  vim.fn.writefile(lines, path)
  return path
end

--- A scratch buffer with `text`, the cursor at byte column `col` (0-based).
---@param text string
---@param col integer
---@param ft? string
local function buffer(text, col, ft)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(b)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { text })
  vim.bo[b].filetype = ft or ""
  vim.api.nvim_win_set_cursor(0, { 1, col })
  return b
end

describe("lsp.tools.deprecated_help.word", function()
  local done_tracking, word, defaults, notes, real_notify

  before_each(function()
    done_tracking = tracker.track()
    for _, mod in ipairs(MODS) do
      package.loaded[mod] = nil
    end
    word = require("lsp.tools.deprecated_help.word")
    defaults = require("lsp.tools.deprecated_help.defaults")
    notes = {}
    real_notify = vim.notify
    vim.notify = function(msg, level)
      notes[#notes + 1] = { msg = tostring(msg), level = level }
    end
  end)

  after_each(function()
    vim.notify = real_notify
    for _, win in ipairs(floats()) do
      pcall(vim.api.nvim_win_close, win, true)
    end
    vim.cmd("silent! helpclose")
    pcall(vim.keymap.del, "n", "<leader>zq")
    done_tracking()
    for _, mod in ipairs(MODS) do
      package.loaded[mod] = nil
    end
  end)

  it("takes the dotted name under the cursor first, then the plain word", function()
    buffer("local x = vim.api.nvim_buf_get_lines(0)", 20)
    assert.are.same(
      { "vim.api.nvim_buf_get_lines", "nvim_buf_get_lines" },
      word.words_under_cursor()
    )
    buffer("foo bar", 4)
    assert.are.same({ "bar" }, word.words_under_cursor())
  end)

  it("shows the runtime help of the word under the cursor in a float, focus stays", function()
    buffer("if vim.tbl_contains(t, x) then end", 8, "lua")
    local win = vim.api.nvim_get_current_win()
    assert.is_true(word.show())
    local f = floats()
    assert.are.equal(1, #f, "no float was opened")
    assert.are.equal(win, vim.api.nvim_get_current_win(), "the focus moved")
    local shown = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(f[1]), 0, 1, false)[1]
    assert.truthy(shown:find("*vim.tbl_contains()*", 1, true), shown)
  end)

  it("falls back to the plain word when the dotted name has no entry", function()
    buffer("local n = vim.api.nvim_buf_get_lines", 20, "lua")
    local match = word.find(word.words_under_cursor(), "lua")
    assert.is_table(match, "nvim_buf_get_lines() was not found")
    assert.are.equal("nvim_buf_get_lines()", match.tag)
  end)

  it("searches the help pages of the filetype first, and finds a tag ending in the word", function()
    local path = page({
      "mylib.txt   A test page",
      "",
      "mylib.frob({x})                                       *mylib.frob()*",
      "    Frobs x.",
      "",
      "vim.tbl_contains({t}, {v})                       *vim.tbl_contains()*",
      "    The page's own text, not the runtime's.",
    })
    word.setup({ help_pages = { lua = { path } } })

    local frob = word.find({ "frob" }, "lua")
    assert.is_table(frob, "the page was not searched")
    assert.are.equal("mylib.frob()", frob.tag)
    assert.are.equal(3, frob.lnum)
    assert.are.same({ "    Frobs x." }, { frob.lines[2] })

    local first = word.find({ "vim.tbl_contains" }, "lua")
    assert.are.equal(path, first.file, "the runtime help won over the page")

    -- another filetype does not see the page
    assert.is_nil(word.find({ "frob" }, "python"))
  end)

  it("resolves a page name on the runtimepath, .txt optional", function()
    assert.is_string(word.resolve_page("luvref"))
    assert.are.equal(word.resolve_page("luvref"), word.resolve_page("luvref.txt"))
    assert.is_nil(word.resolve_page("no-such-help-page-here"))
    word.setup({ help_pages = { lua = { "luvref" } } })
    local match = word.find({ "fs_stat" }, "lua")
    assert.is_table(match)
    assert.are.equal("uv.fs_stat()", match.tag)
  end)

  it("says so when nothing is found, and opens nothing", function()
    buffer("zzqx_no_such_help_word_qq", 3, "lua")
    assert.is_false(word.show())
    assert.are.equal(0, #floats())
    assert.are.equal(1, #notes)
    assert.truthy(
      notes[1].msg:find("No help found for: zzqx_no_such_help_word_qq", 1, true),
      notes[1].msg
    )
  end)

  it("refuses text that is not a word", function()
    assert.is_false(word.show("a\nb"))
    assert.are.equal(0, #floats())
    assert.truthy(notes[1].msg:find("Not a word", 1, true), notes[1].msg)
  end)

  it("display help jumps: :help for a runtime tag, else the page at its line", function()
    defaults.display = "help"
    assert.is_true(word.show("vim.tbl_contains"))
    assert.are.equal("help", vim.bo.buftype)
    assert.are.equal(0, #floats())
    vim.cmd("helpclose")

    -- a space and a `%` in the name: `:split` would split or expand them
    local path = page(
      { "x.txt", "", "", "frobnicate()                               *zz.frobnicate()*" },
      " my%page.txt"
    )
    word.setup({ help_pages = { [""] = { path } } })
    buffer("frobnicate", 0)
    assert.is_true(word.show())
    -- realpath: macOS hands out its temp dir as /var/... and resolves it to /private/var/...
    local real = function(p)
      return vim.fs.normalize(vim.uv.fs_realpath(p) or p)
    end
    assert.are.equal(real(path), real(vim.api.nvim_buf_get_name(0)))
    assert.are.equal("help", vim.bo.filetype)
    assert.is_false(vim.bo.modifiable)
    assert.are.equal(4, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("binds no key by default, the configured one when asked, and warns on a bad value", function()
    -- The config option is gone (keymaps.map.word_help); the tool module set up on its own keeps it.
    assert.is_nil(require("lsp.config.DEFAULTS").tools.deprecated_help.word_keymap)
    require("lsp.tools.deprecated_help").setup({})
    assert.are.equal("", vim.fn.maparg("<leader>zq", "n"))

    word.setup({ word_keymap = 42 })
    assert.truthy(notes[#notes].msg:find("word_keymap", 1, true))

    word.setup({ word_keymap = "<leader>zq" })
    local map = vim.fn.maparg("<leader>zq", "n", false, true)
    assert.are.equal("LSP: Help for the word under the cursor", map.desc)
  end)

  it("drops a malformed help_pages entry with a warning", function()
    word.setup({ help_pages = { lua = { "luvref", 3 }, [1] = "x" } })
    assert.are.same({ lua = { "luvref" } }, defaults.help_pages)
    assert.truthy(notes[#notes].msg:find("help_pages", 1, true))
  end)
end)

describe(":Lsp help", function()
  before_each(function()
    require("lsp.config").setup({})
    require("lsp.bindings.usrcmds").setup()
  end)
  after_each(function()
    for _, win in ipairs(floats()) do
      pcall(vim.api.nvim_win_close, win, true)
    end
  end)

  it("is a route and shows the help of its argument", function()
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion("Lsp ", "cmdline"), "help"))
    vim.cmd("Lsp help tbl_contains")
    assert.are.equal(1, #floats())
  end)
end)
