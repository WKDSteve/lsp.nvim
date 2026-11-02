--- Covers `lsp.core.lua_root`: which structures count, which one is picked for
--- no count / a count, and the cursor landing. The Treesitter tree is the source
--- of truth, so no language server is involved.

local lua_root = require("lsp.core.lua_root")

local SRC = {
  "local M = {}", -- 1
  "",
  "function M.setup(opts)", -- 3
  "  local cfg = {", -- 4
  "    nested = {", -- 5
  "      deep = { x = 1 },", -- 6
  "    },", -- 7
  "    fn = function()", -- 8
  "      return 2", -- 9
  "    end,", -- 10
  "  }", -- 11
  "  return cfg", -- 12
  "end", -- 13
  "",
  "local top = 5", -- 15
  "return M",
}

describe("lsp.core.lua_root", function()
  local buf

  before_each(function()
    vim.cmd("enew!")
    buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, SRC)
    vim.bo[buf].filetype = "lua"
  end)

  after_each(function()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  --- Put the cursor at 1-based line `l`, 0-based column `c` and jump.
  local function jump(l, c, opts)
    vim.api.nvim_win_set_cursor(0, { l, c })
    local ok, why = lua_root.jump(vim.tbl_extend("force", { bufnr = buf }, opts or {}))
    return ok, why, vim.api.nvim_win_get_cursor(0)[1]
  end

  it("goes to the outermost structure without a count", function()
    local ok, _, line = jump(6, 20)
    assert.is_true(ok)
    assert.are.equal(3, line)
  end)

  it("goes N levels up with a count and clamps to the outermost", function()
    -- the innermost structure already starts on this line: stays put
    local ok1, _, one = jump(6, 20, { count = 1 })
    assert.is_false(ok1)
    assert.are.equal(6, one)
    local _, _, two = jump(6, 20, { count = 2 })
    assert.are.equal(5, two)
    local _, _, three = jump(6, 20, { count = 3 })
    assert.are.equal(4, three)
    local _, _, big = jump(6, 20, { count = 99 })
    assert.are.equal(3, big)
  end)

  it("counts a function inside a table as a structure", function()
    local ok, _, line = jump(9, 10, { count = 1 })
    -- innermost structure is the function at line 8; the cursor is inside it
    assert.is_true(ok)
    assert.are.equal(8, line)
  end)

  it("is a no-op with a reason on the head of the root", function()
    local ok, why, line = jump(3, 0)
    assert.is_false(ok)
    assert.is_truthy(why:find("already", 1, true))
    assert.are.equal(3, line)
  end)

  it("is a no-op outside any structure", function()
    local ok, why = jump(15, 0)
    assert.is_false(ok)
    assert.is_truthy(why:find("not inside", 1, true))
  end)

  it("refuses a non-Lua buffer", function()
    vim.bo[buf].filetype = "text"
    local ok, why = jump(6, 20)
    assert.is_false(ok)
    assert.is_truthy(why:find("Lua", 1, true))
  end)

  it("sets the previous-context mark so <C-o> returns", function()
    jump(6, 20)
    vim.cmd("normal! ``")
    assert.are.equal(6, vim.api.nvim_win_get_cursor(0)[1])
  end)
end)
