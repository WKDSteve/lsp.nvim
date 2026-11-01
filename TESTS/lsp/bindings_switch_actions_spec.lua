--- Covers the runtime switch actions of `lsp.bindings.actions` (inlay hints and
--- the code-action indicator). Both are generated from one factory, so the
--- eight entries must keep the same behaviour and cannot drift apart again.

local PAIRS = {
  { prefix = "hints", mod = "lsp.core.inlay_hints" },
  { prefix = "lightbulb", mod = "lsp.core.lightbulb" },
}

describe("lsp.bindings.actions switch actions", function()
  local actions, calls, saved

  before_each(function()
    require("lsp.config").setup({})
    actions = require("lsp.bindings.actions")
    calls = {}
    saved = {}
    for _, p in ipairs(PAIRS) do
      saved[p.mod] = package.loaded[p.mod]
      package.loaded[p.mod] = {
        toggle = function(ft)
          calls[#calls + 1] = { p.prefix, "toggle", ft }
        end,
        set = function(on, ft)
          calls[#calls + 1] = { p.prefix, "set", on, ft }
        end,
      }
    end
  end)

  after_each(function()
    for mod, old in pairs(saved) do
      package.loaded[mod] = old
    end
    vim.bo[0].filetype = ""
  end)

  for _, p in ipairs(PAIRS) do
    describe(p.prefix, function()
      it("toggles, switches on and off globally", function()
        actions[p.prefix .. "_toggle"]()
        actions[p.prefix .. "_on"]()
        actions[p.prefix .. "_off"]()
        assert.are.same({
          { p.prefix, "toggle", nil },
          { p.prefix, "set", true, nil },
          { p.prefix, "set", false, nil },
        }, calls)
      end)

      it("toggles for the current filetype", function()
        vim.bo[0].filetype = "lua"
        actions[p.prefix .. "_toggle_filetype"]()
        assert.are.same({ { p.prefix, "toggle", "lua" } }, calls)
      end)

      it("warns instead of toggling when the buffer has no filetype", function()
        local said = {}
        local real = package.loaded["lib.nvim.notify"]
        package.loaded["lib.nvim.notify"] = {
          create = function()
            return {
              warn = function(msg)
                said[#said + 1] = msg
              end,
            }
          end,
        }
        actions[p.prefix .. "_toggle_filetype"]()
        package.loaded["lib.nvim.notify"] = real
        assert.are.same({}, calls)
        assert.are.same({ "this buffer has no filetype" }, said)
      end)

      it("is a no-op when the module cannot be loaded", function()
        package.loaded[p.mod] = nil
        package.preload[p.mod] = function()
          error("boom")
        end
        assert.has_no.errors(function()
          actions[p.prefix .. "_toggle"]()
          actions[p.prefix .. "_on"]()
          actions[p.prefix .. "_toggle_filetype"]()
        end)
        package.preload[p.mod] = nil
      end)
    end)
  end

  it("generates both families from one factory instead of copies", function()
    local path = vim.api.nvim_get_runtime_file("lua/lsp/bindings/actions.lua", false)[1]
    local body = table.concat(vim.fn.readfile(path), "\n")
    local _, n = body:gsub("make_switch_actions%(", "")
    assert.are.equal(3, n, "one definition and one call per family")
    assert.is_nil(body:find("function M.lightbulb_toggle", 1, true))
    assert.is_nil(body:find("function M.hints_toggle", 1, true))
  end)
end)
