---@module 'lsp.core.env_links.parse'
---@brief Link parsing of `lsp.core.env_links`: the link under a column, every link of a line, and the masks.
---@description
--- The first third of `env_links.lua`'s Markdown handling, split out so the
--- inline-link / reference-definition rules can be read and specified on their
--- own: `target_at(line, col)`, `links(line)`, and the two masks that blank
--- inline code and HTML comments out byte for byte. Pure string functions.
---
--- The module returns a builder, not a table: the size limits
--- (`MAX_LINE_BYTES`, `MAX_TARGET_BYTES`) live on the `env_links` facade, where
--- tests lower them, so they are read from `dep.limits` at call time, and the
--- facade must not be required back (a cycle).
---
---@see lsp.core.env_links
---@see lsp.core.env_links.blocks

---@class LspNvim.EnvLink.ParseDeps
---@field limits table # `env_links`; `MAX_LINE_BYTES` and `MAX_TARGET_BYTES` are read from it at call time.

---@param dep LspNvim.EnvLink.ParseDeps
---@return table
return function(dep)
  local lim = dep.limits
  local X = {}

  ---@internal
  --- Bytes of link targets `target_at` examines in one call, summed over all the
  --- links it tries: a few targets of the longest allowed length, and a hundred
  --- times what the links around any real position add up to.
  ---@type integer
  local TARGET_SCAN_BUDGET = 4 * lim.MAX_TARGET_BYTES

  ---@internal
  --- Whether byte `b` is what Lua's `%s` matches.
  ---@param b integer|nil
  ---@return boolean
  local function is_space(b)
    return b == 32 or (b ~= nil and b >= 9 and b <= 13)
  end

  ---@internal
  --- Parse the target that starts at byte `i` of an inline link's `(`...`)`.
  --- A `<...>` target may hold spaces; a bare one ends at whitespace or at the
  --- unmatched `)`, and may be followed by a title.
  ---
  --- Bounded by `MAX_TARGET_BYTES`, and hops from one byte that matters to the
  --- next with `find` instead of looking at every byte: `[a]($X/[a]($X/...`
  --- makes every link's target run to the end of the line, and a scan per link
  --- over the rest of the line is quadratic.
  ---@param line string
  ---@param i integer # First byte after `(`.
  ---@return string|nil target
  ---@return integer|nil close # Byte of the closing `)`, or the last byte seen.
  ---@return integer|nil after # First byte after the destination.
  local function parse_target(line, i)
    if line:byte(i) == 60 then -- "<"
      local gt = line:find(">", i + 1, true)
      if not gt or gt - i - 1 > lim.MAX_TARGET_BYTES then
        return nil, nil
      end
      return line:sub(i + 1, gt - 1), line:find(")", gt + 1, true) or gt, gt + 1
    end

    local depth, j = 0, i
    while true do
      local k = line:find("[%s()]", j)
      if not k then
        j = #line + 1 -- runs to the end of the line: a link still being typed
        break
      end
      if k - i > lim.MAX_TARGET_BYTES then
        return nil, nil -- longer than any real target: not cut short, refused
      end
      local c = line:byte(k)
      if c == 40 then -- "("
        depth = depth + 1
      elseif c == 41 then -- ")"
        if depth == 0 then
          j = k
          break
        end
        depth = depth - 1
      else -- whitespace
        j = k
        break
      end
      j = k + 1
    end
    if j == i then
      -- Empty or blank-led target (`[x]()`, `[x]( p)`, a trailing `[x](`): found
      -- by the first `find`, so it costs one byte, not a whole target.
      return nil, i - 1
    end
    if j - i > lim.MAX_TARGET_BYTES then
      return nil, nil
    end
    return line:sub(i, j - 1), line:find(")", j, true) or (j - 1), j
  end

  ---@internal
  --- The target of a reference definition line, `[label]: target`, and the byte
  --- span of that target within the line (`<>` not included).
  ---
  --- `<...>` first: like an inline `(<...>)` target it may hold spaces (a path
  --- under "Program Files"), and `%S+` alone would cut it at the first one and
  --- return `<$R/my`. Two anchored patterns, each linear in a line of at most
  --- `MAX_LINE_BYTES`; the target is held to the same limit as an inline one.
  ---@param line string
  ---@return string|nil target
  ---@return integer|nil first # 1-based byte of the target's first character.
  ---@return integer|nil last # 1-based byte of its last character.
  local function ref_definition(line)
    local first, ref, after = line:match("^%s*%[[^%]]+%]:%s*()(<[^>]*>)()")
    local angled = ref ~= nil
    if not ref then
      first, ref, after = line:match("^%s*%[[^%]]+%]:%s*()(%S+)()")
    end
    if not ref then
      return nil
    end
    local last = after - 1
    if angled then
      ref = ref:sub(2, -2)
      first, last = first + 1, last - 1
    end
    if #ref > lim.MAX_TARGET_BYTES then
      return nil
    end
    return ref, first, last
  end

  ---@class LspNvim.EnvLink.Span
  ---@field target string # As written, `#fragment` included, `<>` not.
  ---@field first integer # 1-based byte of the target's first character.
  ---@field last integer # 1-based byte of its last character.

  ---@class LspNvim.EnvLink.Found : LspNvim.EnvLink.Span
  ---@field lnum integer # 0-based line.

  --- Bytes of link targets `links` examines in one line, summed over its links.
  ---@type integer
  local LINKS_SCAN_BUDGET = 2 * lim.MAX_LINE_BYTES

  ---@internal
  --- The inline links of one line, found in one left-to-right pass over its
  --- brackets -- the one rule set `target_at` and `links` both go by.
  ---
  --- A stack holds the `[` not yet closed, and a `]` closes the innermost. A `](`
  --- right after it makes an inline link whose text starts there. The text may
  --- hold balanced brackets and an image (the badge pattern,
  --- `[![alt](img)](target)`), and a backslash escapes the byte after it (`\]`).
  --- Inner links are completed, and so found, before the ones around them.
  ---
  --- A link cannot contain a link (CommonMark): once one is formed, the `[` still
  --- open around it are dead and their `](` is text -- except an image's, whose
  --- description may hold a link. `dead` is how many of the lowest stack entries
  --- that is true for, so it costs nothing per bracket.
  ---
  --- With `col` (column mode) it returns the target of the link that holds the
  --- byte column `col`, and skips the targets that cannot reach it: a link that
  --- starts past `col`, or whose target starts more than a target's length before
  --- it, is not parsed -- unless a `[` is open around it, because whether it
  --- forms decides whether that one is dead. Without `col`, it appends every
  --- link to `found`.
  ---
  --- The target bytes examined are budgeted (`TARGET_SCAN_BUDGET`,
  --- `LINKS_SCAN_BUDGET`): nesting lets one hostile line make thousands of `](`
  --- each parse a target that runs to the limit (273 ms measured, 10000 `[` and
  --- 5000 `](`). A link that fails to parse is charged what the parse cost: the
  --- limit for one that ran on, a byte for an empty target.
  ---@param line string
  ---@param col integer|nil
  ---@param found LspNvim.EnvLink.Span[]|nil
  ---@return string|nil target # Column mode only.
  local function walk(line, col, found)
    local opens, imgs, n = {}, {}, 0 ---@type integer[], boolean[], integer
    local dead, escaped = 0, 0 -- `escaped`: the byte the last backslash escaped
    local budget = col and TARGET_SCAN_BUDGET or LINKS_SCAN_BUDGET
    local pos = 1
    while true do
      local i = line:find("[%[%]\\]", pos)
      if not i then
        break
      end
      local c = line:byte(i)
      pos = i + 1
      if c == 92 then -- "\": the next byte is text
        pos = i + 2
        escaped = i + 1
      elseif c == 91 then -- "["
        n = n + 1
        opens[n] = i
        imgs[n] = i > 1 and line:byte(i - 1) == 33 and escaped ~= i - 1 -- an unescaped "!"
      elseif n > 0 then -- "]"
        local open, img = opens[n], imgs[n]
        local live = img or n > dead
        n = n - 1
        if dead > n then
          dead = n
        end
        if live and line:byte(i + 1) == 40 then -- "]("
          local reaches = true
          if col then
            -- Counting the `>` and `)` that close a `<...>` target as part of
            -- the link.
            reaches = open <= col and i + 4 + lim.MAX_TARGET_BYTES >= col
          end
          if reaches or n > 0 then
            local target, close, after = parse_target(line, i + 2)
            if target and close then
              if col == nil then
                local first = i + 2 + (line:byte(i + 2) == 60 and 1 or 0)
                found[#found + 1] = { target = target, first = first, last = first + #target - 1 }
              elseif reaches and col <= close then
                return target
              end
            end
            -- The links around it are dead only when this one really is a link:
            -- the destination is followed by `)` or a title. `[x](a b)` and
            -- `[x](foo` (still being typed) are answered, leniently, but they
            -- are text to CommonMark and must not take the enclosing link with
            -- them. `[x]()` is a link.
            local formed = false
            if target then
              local nxt = after and line:find("%S", after)
              local b = nxt and line:byte(nxt)
              formed = b == 41 or b == 34 or b == 39 or b == 40
            elseif close and line:byte(i + 2) == 41 then
              formed = true
            end
            if formed and not img then
              dead = n
            end
            budget = budget - (close and (close - i) or lim.MAX_TARGET_BYTES)
            if budget < 0 then
              break
            end
          end
          -- Links come left to right, but an enclosing one is only completed
          -- after the inner ones: nothing further right can hold `col` once
          -- this one starts past it AND no `[` still open starts before it.
          if col and open > col and (n == 0 or opens[1] > col) then
            break
          end
        end
      end
    end
    return nil
  end

  --- The link target of the Markdown link the byte column `col` (1-based) is
  --- on: anywhere in `[text](target)` / `![alt](target)`, or anywhere on a
  --- reference definition line `[label]: target`.
  ---
  --- Works on one line, which is all a link is: this is not a Markdown parser,
  --- and a link broken across lines is not one marksman resolves either.
  ---@param line any # A string; anything else answers nil.
  ---@param col any # A number (1-based byte column); anything else answers nil.
  ---@return string|nil target # As written, `<>` and `#fragment` included.
  function X.target_at(line, col)
    -- Types first (ERR-02): a hover asks this about whatever it was handed, and
    -- "no link here" is the fail-open answer. The comparison with `#line` comes
    -- after the type check on purpose.
    --
    -- A hover or a `gd` on a minified or generated line must not be able to
    -- stall the editor. The scan below is linear in the line (measured before
    -- it was: 1.2 s on 20000 `[`), this cap only keeps it short.
    if type(line) ~= "string" or type(col) ~= "number" or #line > lim.MAX_LINE_BYTES then
      return nil
    end

    local target = walk(line, col, nil)
    if target then
      return target
    end

    -- A reference definition is a link too, and answers from any column of its
    -- line, the title's included.
    return (ref_definition(line))
  end

  -- ----------------------------------------------------------------------------
  -- Every link in a buffer
  -- ----------------------------------------------------------------------------

  --- Every link on one line: `[text](target)`, `![alt](target)`, and a reference
  --- definition `[label]: target`, with the span of each target. The same bracket
  --- rules as `target_at`, which answers for one column; this answers for all.
  ---@param line any
  ---@return LspNvim.EnvLink.Span[]
  function X.links(line)
    local found = {} ---@type LspNvim.EnvLink.Span[]
    if type(line) ~= "string" or #line > lim.MAX_LINE_BYTES then
      return found
    end

    walk(line, nil, found)

    local ref, first, last = ref_definition(line)
    if ref and first and last then
      found[#found + 1] = { target = ref, first = first, last = last }
    end
    return found
  end

  --- `text` with the inside of every code span (`` `x` ``, ``` ``x`` ```) blanked
  --- out, byte for byte, so columns still line up. A span ends at the next run of
  --- exactly as many backticks; a run with none stays text, as in CommonMark.
  ---
  --- A backslash escapes a backtick only outside a span: an odd number of them
  --- right before a run makes it open with one backtick less, and a run that ends
  --- a span counts in full (`C:\` is a span that ends in a backslash).
  ---
  --- Linear: the runs are matched from the right in one pass instead of searching
  --- ahead from each opener, which a line of backticks of a hundred different
  --- lengths would turn quadratic.
  ---@param text string
  ---@return string
  function X.mask_code_spans(text)
    if not text:find("`", 1, true) then
      return text
    end

    local starts, stops, escaped = {}, {}, {}
    local pos = 1
    while true do
      local s, e = text:find("`+", pos)
      if not s then
        break
      end
      local b = s - 1 -- an odd number of backslashes right before the run
      while b >= 1 and text:byte(b) == 92 do
        b = b - 1
      end
      starts[#starts + 1], stops[#stops + 1] = s, e
      escaped[#escaped + 1] = (s - 1 - b) % 2 == 1
      pos = e + 1
    end

    local next_same, next_less, latest = {}, {}, {} ---@type table<integer, integer>, table<integer, integer>, table<integer, integer>
    for k = #starts, 1, -1 do
      local len = stops[k] - starts[k] + 1
      next_same[k] = latest[len]
      next_less[k] = latest[len - 1]
      latest[len] = k
    end

    local out, from, k = {}, 1, 1
    while k <= #starts do
      local first = starts[k]
      local close ---@type integer|nil
      if escaped[k] then
        first = first + 1 -- the escaped backtick is text, the rest of the run opens
        close = next_less[k]
      else
        close = next_same[k]
      end
      if close and first <= stops[k] then
        out[#out + 1] = text:sub(from, first - 1)
        out[#out + 1] = (" "):rep(stops[close] - first + 1)
        from = stops[close] + 1
        k = close + 1
      else
        k = k + 1
      end
    end
    out[#out + 1] = text:sub(from)
    return table.concat(out)
  end

  --- `text` with every HTML comment (`<!-- ... -->`, also `<!-->` and `<!--->`,
  --- as in CommonMark) blanked out, byte for byte, so columns still line up. A
  --- `<!--` that is never closed stays text. Run it on text whose code spans are
  --- already blanked (`mask_code_spans`): a `<!--` shown in a span is no comment.
  ---@param text string
  ---@return string
  function X.mask_html_comments(text)
    if not text:find("<!--", 1, true) then
      return text
    end
    local out, from = {}, 1
    while true do
      local s = text:find("<!--", from, true)
      if not s then
        break
      end
      local _, e = text:find("-->", s + 2, true)
      if not e then
        break
      end
      out[#out + 1] = text:sub(from, s - 1)
      out[#out + 1] = text:sub(s, e):gsub("[^\n]", " ")
      from = e + 1
    end
    out[#out + 1] = text:sub(from)
    return table.concat(out)
  end

  X.is_space = is_space
  return X
end
