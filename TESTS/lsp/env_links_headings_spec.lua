--- Covers `lsp.core.env_links.headings`, the pure heading-text helpers split out of
--- `lsp.core.env_links`. The builder takes its three host helpers as `dep`, so the
--- module is exercised here without the facade; one case goes through the facade
--- to prove the wiring (the limit is read at call time).

local function build(overrides)
  local dep = {
    max_heading_bytes = function()
      return 1000
    end,
    mask_code_spans = function(text)
      return text
    end,
    is_space = function(b)
      return b == 32 or b == 9
    end,
    columns = function(s)
      return #s
    end,
  }
  for k, v in pairs(overrides or {}) do
    dep[k] = v
  end
  return require("lsp.core.env_links.headings")(dep)
end

describe("lsp.core.env_links.headings", function()
  it("builds the GitHub-style anchor of a title", function()
    local H = build()
    assert.are.equal("hello-world", H.slug("Hello, World!"))
    assert.are.equal("übersicht", H.slug("Übersicht"))
  end)

  it("drops a NUL before lowercasing instead of raising", function()
    local H = build()
    assert.are.equal("ab", H.lower("A\0B"))
  end)

  it("takes an ATX heading title and ignores ordinary lines", function()
    local H = build()
    assert.are.equal("Title", H.heading_title("## Title"))
    assert.is_nil(H.heading_title("no hash here"))
  end)

  it("refuses a heading longer than the host limit", function()
    local H = build({
      max_heading_bytes = function()
        return 5
      end,
    })
    assert.is_nil(H.heading_title("# a much longer heading"))
  end)

  it("recognises a setext underline only within the allowed indent", function()
    local H = build()
    assert.is_true(H.is_setext_underline("===", 0))
    assert.is_true(H.is_setext_underline("---", 0))
    assert.is_false(H.is_setext_underline("text", 0))
  end)

  it("is wired into the facade: a lowered limit reaches the helper", function()
    local EL = require("lsp.core.env_links")
    local saved = EL.MAX_HEADING_BYTES
    EL.MAX_HEADING_BYTES = 4
    local ok, err = pcall(function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      local path = dir .. "/x.md"
      vim.fn.writefile({ "# Short", "# This heading is longer than four bytes" }, path)
      EL.clear_cache()
      local index = EL.heading_index(path)
      assert.is_nil(index["this-heading-is-longer-than-four-bytes"])
    end)
    EL.MAX_HEADING_BYTES = saved
    EL.clear_cache()
    assert(ok, err)
  end)
end)
