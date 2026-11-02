--- Covers `lsp.core.env_links.parse` and `lsp.core.env_links.blocks`, the link parser and the
--- block state machine split out of `lsp.core.env_links`. Both are built from plain `dep`
--- tables here (no facade); one case per module goes through the facade to prove the wiring:
--- the limits live on the facade and are read at call time.

local function build_parse(limits)
  return require("lsp.core.env_links.parse")({
    limits = limits or { MAX_LINE_BYTES = 20000, MAX_TARGET_BYTES = 4096 },
  })
end

local function build_blocks(P, limits)
  return require("lsp.core.env_links.blocks")({
    limits = limits or { MAX_LINE_BYTES = 20000, MAX_SCANNED_LINKS = 2000 },
    is_env_target = function(target)
      return type(target) == "string" and target:sub(1, 1) == "$"
    end,
    links = P.links,
    target_at = P.target_at,
    mask_code_spans = P.mask_code_spans,
    mask_html_comments = P.mask_html_comments,
  })
end

describe("lsp.core.env_links.parse", function()
  it("finds every inline link target of a line", function()
    local P = build_parse()
    local found = P.links("[a]($X/a.md) and [b](<$Y/b c.md>)")
    assert.are.equal(2, #found)
    assert.are.equal("$X/a.md", found[1].target)
    assert.are.equal("$Y/b c.md", found[2].target)
  end)

  it("returns the target under a column and nil off the link", function()
    local P = build_parse()
    local line = "see [a]($X/a.md) now"
    assert.are.equal("$X/a.md", P.target_at(line, 12))
    assert.is_nil(P.target_at(line, 1))
  end)

  it("reads the line limit from the limits table at call time", function()
    local limits = { MAX_LINE_BYTES = 10, MAX_TARGET_BYTES = 4096 }
    local P = build_parse(limits)
    assert.are.same({}, P.links("[a]($X/a.md) is longer than ten bytes"))
    limits.MAX_LINE_BYTES = 20000
    assert.are.equal(1, #P.links("[a]($X/a.md)"))
  end)

  it("blanks inline code and HTML comments byte for byte", function()
    local P = build_parse()
    local text = "a `[x]($B/c)` <!-- [y]($D) --> z"
    assert.are.equal(#text, #P.mask_code_spans(text))
    assert.is_nil(P.mask_code_spans(text):find("$B", 1, true))
    assert.are.equal(#text, #P.mask_html_comments(text))
    assert.is_nil(P.mask_html_comments(text):find("$D", 1, true))
  end)

  it("is wired into the facade: a lowered limit reaches the parser", function()
    local EL = require("lsp.core.env_links")
    local saved = EL.MAX_LINE_BYTES
    EL.MAX_LINE_BYTES = 5
    local ok, err = pcall(function()
      assert.are.same({}, EL.links("[a]($X/a.md)"))
    end)
    EL.MAX_LINE_BYTES = saved
    assert(ok, err)
    assert.are.equal(1, #EL.links("[a]($X/a.md)"))
  end)
end)

describe("lsp.core.env_links.blocks", function()
  it("marks the lines of a fenced code block as no document text", function()
    local B = build_blocks(build_parse())
    local lines = { "text", "```", "[a]($X/a.md)", "```", "after" }
    assert.is_false(B.fenced_at(lines, 1))
    assert.is_true(B.fenced_at(lines, 3))
    assert.is_false(B.fenced_at(lines, 5))
  end)

  it("scans env links outside code only", function()
    local B = build_blocks(build_parse())
    local found = B.scan({ "[a]($X/a.md)", "```", "[b]($X/b.md)", "```", "[c](plain.md)" })
    assert.are.equal(1, #found)
    assert.are.equal("$X/a.md", found[1].target)
    assert.are.equal(0, found[1].lnum)
  end)

  it("caps the scan at the limit it is given", function()
    local B = build_blocks(build_parse(), { MAX_LINE_BYTES = 20000, MAX_SCANNED_LINKS = 1 })
    assert.are.equal(1, #B.scan({ "[a]($X/a.md) [b]($X/b.md)", "[c]($X/c.md)" }))
  end)

  it("counts a tab as the next multiple of four columns", function()
    local B = build_blocks(build_parse())
    assert.are.equal(4, B.columns("\t"))
    assert.are.equal(5, B.columns(" \t "))
  end)

  it("is wired into the facade", function()
    local EL = require("lsp.core.env_links")
    assert.is_true(EL.fenced_at({ "~~~", "x", "~~~" }, 2))
  end)
end)
