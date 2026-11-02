---@module 'lsp.core.env_links.blocks'
---@brief Block structure of `lsp.core.env_links`: fences, quotes, lists, front matter, paragraphs.
---@description
--- The Markdown block state machine, line by line, split out of `env_links.lua`:
--- which lines are no document text (`fenced_at`), the masked paragraph text
--- (`masked_line_at`), every env link of a buffer (`scan`) and the link being
--- typed at a column (`typing_at`). It builds on the link parser
--- (`env_links.parse`), whose functions come in as `dep`.
---
--- The module returns a builder for the same reason as `env_links.headings`:
--- `env_links` owns the limits and `is_env_target`, and must not be required back.
---
---@see lsp.core.env_links
---@see lsp.core.env_links.parse

---@class LspNvim.EnvLink.BlocksDeps
---@field limits table # `env_links`; `MAX_LINE_BYTES` and `MAX_SCANNED_LINKS` are read from it at call time.
---@field is_env_target fun(target: any): boolean
---@field links fun(line: string): LspNvim.EnvLink.Span[]
---@field target_at fun(line: string, col: integer): LspNvim.EnvLink.Span|nil
---@field mask_code_spans fun(text: string): string
---@field mask_html_comments fun(text: string): string

---@param dep LspNvim.EnvLink.BlocksDeps
---@return table
return function(dep)
  local lim = dep.limits
  local X = {}

  ---@class LspNvim.EnvLink.Fence
  ---@field char string # "`" or "~".
  ---@field len integer # How many of them opened the block.
  ---@field quote integer # Block quote depth the block was opened at.
  ---@field indent integer # Columns of the list item it was opened in (0: none).

  ---@internal
  --- The block quote depth of `line` (how many `>`), and the line without them.
  ---@param line string
  ---@return integer depth
  ---@return string rest
  ---@return string[] leads # The blanks before each `>`.
  local function unquote(line)
    -- One `>` and at most one blank after it, per level: what follows keeps its
    -- own indentation (`>   [x]` is a continuation line of a list item).
    local pos, depth, leads = 1, 0, {}
    while true do
      local _, e, lead = line:find("^([ \t]*)>[ \t]?", pos)
      if not e then
        break
      end
      depth = depth + 1
      leads[depth] = lead
      pos = e + 1
    end
    if depth == 0 then
      return 0, line, leads
    end
    return depth, line:sub(pos), leads
  end

  ---@internal
  --- The width in columns of `s`, a tab going to the next multiple of four.
  ---@param s string
  ---@return integer
  local function columns(s)
    local w = 0
    for k = 1, #s do
      w = s:byte(k) == 9 and w + 4 - w % 4 or w + 1
    end
    return w
  end

  ---@internal
  --- The state of fenced-code-block tracking after `line`, and whether the line
  --- is no document text: the fence line itself, or a line inside the block.
  ---
  --- CommonMark's rules, as far as a line-by-line pass can follow them:
  ---   * a block ends at a fence of the same character at least as long as the
  ---     opener, followed by nothing but blanks (so a "```js" inside a block is
  ---     content, not its end);
  ---   * the info string of a backtick fence holds no backtick (a line that
  ---     starts with "```x``` is inline code" is a paragraph, not an opener);
  ---   * a fence may open behind a list marker (`- ```md`), where it ends with
  ---     the list item (a line indented less than the item's content), and inside
  ---     a block quote (`> ```md`), where it ends with the quote; a fence line
  ---     closes a block only at the block's own quote depth.
  --- (A single on/off toggle closed a `~~~` block at the first inner "```" line
  --- and a four-backtick block at an inner three-backtick one, and the lines
  --- after it were read as document; one such slip inverted the rest of the file.)
  ---@param fence LspNvim.EnvLink.Fence|nil # State before `line`; nil outside a block.
  ---@param line string
  ---@return LspNvim.EnvLink.Fence|nil fence
  ---@return boolean skip
  local function fence_step(fence, line)
    local quote, rest, leads = unquote(line)
    if fence and quote < fence.quote then
      fence = nil -- the block quote that held the block ended, and the block with it
    end
    -- The list item the block was opened in ends at a line indented less than its
    -- content. Inside a deeper block quote the indentation is the blanks before the
    -- `>` (a `>` that starts before the content column is a quote of its own,
    -- and one at the content column is code), otherwise the blanks that remain
    -- after the quote prefix.
    if fence and fence.indent > 0 and rest:find("%S") then
      local cols = quote > fence.quote and columns(leads[fence.quote + 1])
        or columns(rest:match("^[ \t]*"))
      if cols < fence.indent then
        fence = nil
      end
    end
    local indent = 0
    if not fence then
      local item = rest:match("^%s*[-*+]%s+()") or rest:match("^%s*%d+[.)]%s+()")
      if item then
        indent = columns(rest:sub(1, item - 1))
        rest = rest:sub(item)
      end
    end

    local char, run, info = "`", rest:match("^%s*(```+)([^`]*)$")
    if not run then
      char, run, info = "~", rest:match("^%s*(~~~+)(.*)$")
    end
    if not run then
      return fence, fence ~= nil
    end
    if not fence then
      return { char = char, len = #run, quote = quote, indent = indent }, true
    end
    if
      quote == fence.quote
      and char == fence.char
      and #run >= fence.len
      and info:match("^%s*$")
    then
      return nil, true
    end
    return fence, true
  end

  ---@internal
  --- Does `line` start a block of its own (or is it blank)? Then it cannot go on
  --- the paragraph above it: blank, heading, block quote, table row, list item,
  --- thematic break.
  ---@param line string
  ---@param head? string # The first line of the paragraph the line would go on.
  ---@return boolean
  local function opens_block(line, head)
    return line:find("^%s*$") ~= nil
      or line:find("^%s*[>|]") ~= nil
      or line:find("^%s*#+%s") ~= nil
      or line:find("^%s*#+$") ~= nil
      or line:find("^%s*[-*+]%s") ~= nil
      or line:find("^%s*1[.)]%s") ~= nil
      -- Another number cannot interrupt a paragraph, but after a numbered item it
      -- is the next item of the list.
      or (head ~= nil and line:find("^%s*%d+[.)]%s") ~= nil and head:find("^%s*%d+[.)]%s") ~= nil)
      or line:find("^%s*[-*_=][-*_= ]*[-*_=][-*_= ]*[-*_=]") ~= nil
  end

  ---@internal
  --- The last line of a YAML front matter: `---` on the first line, up to the next
  --- `---` or `...`. 0 when there is none, or it is not closed.
  ---@param lines string[]
  ---@return integer
  local function front_matter_end(lines)
    if lines[1] and lines[1]:match("^%-%-%-%s*$") then
      for k = 2, #lines do
        if lines[k]:match("^%-%-%-%s*$") or lines[k]:match("^%.%.%.%s*$") then
          return k
        end
      end
    end
    return 0
  end

  ---@class LspNvim.EnvLink.Blocks
  ---@field fence LspNvim.EnvLink.Fence|nil # The fenced code block the line is in.
  ---@field comment LspNvim.EnvLink.Comment|nil # The HTML comment block (`<!--` up to the line with `-->`) the line is in.
  ---@field lists integer[] # Content columns of the open list items, innermost last.
  ---@field lists_quote integer # Block quote depth `lists` belong to.
  ---@field para boolean # The line before was paragraph text (an indented line goes on it).

  ---@class LspNvim.EnvLink.Comment
  ---@field quote integer # Block quote depth the block was opened at.
  ---@field indent integer # Content column of the list item it was opened in (0: none).

  ---@internal
  --- A fresh `block_step` state, for the first line of a document.
  ---@return LspNvim.EnvLink.Blocks
  local function new_blocks()
    return { lists = {}, lists_quote = 0, para = false }
  end

  --- The list item marker of `rest` (a line without its quote prefix): the
  --- columns of the blanks before it, and the column its content starts at.
  ---@param rest string
  ---@return integer|nil lead
  ---@return integer|nil content
  local function list_item(rest)
    local item = rest:match("^[ \t]*[-*+][ \t]+()") or rest:match("^[ \t]*%d+[.)][ \t]+()")
    if not item or not rest:find("%S", item) then
      return nil -- an empty item (`-`) or a thematic break of one marker
    end
    -- `- - -` and `* * *` are thematic breaks, not items.
    if rest:find("^[ \t]*[-*_][ \t]*[-*_][ \t]*[-*_][-*_ \t]*$") then
      return nil
    end
    return columns(rest:match("^[ \t]*")), columns(rest:sub(1, item - 1))
  end

  ---@internal
  --- Advance the block tracking `st` past `line`, and say whether the line is no
  --- document text: a fenced code block (`fence_step`), an indented code block, or
  --- an HTML comment block.
  ---
  --- An indented code block is a line indented four columns past the content of
  --- the list item it is in (past the margin outside a list), that does not go on
  --- a paragraph: an indented line right after paragraph text is its
  --- continuation. The list items are followed by their content columns, so a
  --- list continuation paragraph (`- a`, blank, `  more`) stays text. An HTML
  --- comment block starts at a line beginning with `<!--` (up to three blanks
  --- past the content of the list item it is in) and ends at the first line that
  --- holds `-->`, or with the block quote or list item it was opened in (no lazy
  --- line goes on an HTML block), as in CommonMark; a comment in running text is
  --- masked per paragraph (`masked_lines`).
  ---@param st LspNvim.EnvLink.Blocks
  ---@param line string
  ---@return boolean skip
  local function block_step(st, line)
    local quote, rest, leads = unquote(line)
    local blank = not rest:find("%S")
    local comment = st.comment
    if comment then
      -- Measured as `fence_step` measures a fenced block's list item.
      local ended = quote < comment.quote
      if not ended and comment.indent > 0 and not blank then
        local cols = quote > comment.quote and columns(leads[comment.quote + 1])
          or columns(rest:match("^[ \t]*"))
        ended = cols < comment.indent
      end
      if not ended then
        if line:find("-->", 1, true) then
          st.comment = nil
        end
        st.para = false
        return true
      end
      st.comment = nil -- the line after the block is read as any other
    end
    local underline = false -- a setext underline: it ends the paragraph above it
    if not st.fence and not blank then
      if quote ~= st.lists_quote then
        st.lists, st.lists_quote = {}, quote
      end
      local lists = st.lists
      local lead = columns(rest:match("^[ \t]*"))
      if not st.para then
        while #lists > 0 and lists[#lists] > lead do
          lists[#lists] = nil -- a line left of an item's content ends the item
        end
        if lead >= (lists[#lists] or 0) + 4 then
          return true
        end
      end
      local inside = lead < (lists[#lists] or 0) + 4 -- not a paragraph continuation line
      if inside and rest:find("^[ \t]*<!%-%-") then
        -- An HTML block is no lazy line: it belongs to the innermost item whose
        -- content it reaches.
        while #lists > 0 and lists[#lists] > lead do
          lists[#lists] = nil
        end
        if not rest:find("-->", 1, true) then
          st.comment = { quote = quote, indent = lists[#lists] or 0 }
        end
        st.para = false
        return true
      end
      underline = st.para
        and inside
        and (rest:find("^[ \t]*=+[ \t]*$") or rest:find("^[ \t]*%-+[ \t]*$")) ~= nil
      local item_lead, content = list_item(rest)
      if item_lead then
        while #lists > 0 and lists[#lists] > item_lead do
          lists[#lists] = nil
        end
        lists[#lists + 1] = content
      end
    end
    local skip
    st.fence, skip = fence_step(st.fence, line)
    if skip then
      st.para = false
      return true
    end
    st.para = not blank
      and not underline
      and not rest:find("^%s*#+%s")
      and not rest:find("^%s*#+$")
      and not rest:find("^%s*[-*_=][-*_= ]*[-*_=][-*_= ]*[-*_=]%s*$")
    return false
  end

  ---@internal
  --- Walk the paragraphs of a buffer's lines, front matter, code blocks (fenced
  --- and indented) and HTML comment blocks left out (`block_step`): `visit(para)`
  --- gets each one as a list of `{ lnum, line }` (`lnum` is 0-based) and answers
  --- true to stop the walk.
  ---
  --- A paragraph ends at a blank line, a fence, or a line that opens a block of its
  --- own (`opens_block`), and is cut at `MAX_LINE_BYTES`. The lines of a block
  --- quote at one depth are one paragraph (judged without their `>`), and so is a
  --- line without `>` that goes on one (a lazy continuation line).
  ---@param lines string[]
  ---@param visit fun(para: { lnum: integer, line: string }[]): boolean|nil
  ---@return nil
  local function each_paragraph(lines, visit)
    local para, bytes = {}, 0 ---@type { lnum: integer, line: string }[], integer
    local para_quote, head = 0, nil ---@type integer, string|nil # Quote depth and unquoted first line of `para`.
    local stopped = false

    --- Hand the paragraph collected so far to `visit`.
    ---@return nil
    local function flush()
      if #para == 0 then
        return
      end
      local current = para
      para, bytes = {}, 0
      if visit(current) == true then
        stopped = true
      end
    end

    local st = new_blocks()
    for k = front_matter_end(lines) + 1, #lines do
      local line = lines[k]
      if block_step(st, line) or #line > lim.MAX_LINE_BYTES then
        flush()
      else
        local quote, rest = unquote(line)
        local goes_on = #para > 0
          and (quote == para_quote or quote == 0)
          and not opens_block(rest, head)
          and bytes + #line <= lim.MAX_LINE_BYTES
        if not goes_on then
          flush()
        end
        if not stopped and rest:find("%S") then
          if #para == 0 then
            para_quote, head = quote, rest
          end
          para[#para + 1] = { lnum = k - 1, line = line }
          bytes = bytes + #line + 1
        end
        if rest:find("^%s*|") or rest:find("^%s*#+%s") or rest:find("^%s*#+$") then
          flush() -- a heading or a table row is a block of one line
        end
      end
      if stopped then
        return
      end
    end
    flush()
  end

  ---@internal
  --- The lines of a paragraph with the inside of every code span blanked out (see
  --- `mask_code_spans`), cut by offset, not by splitting on "\n": a span that wraps
  --- blanks the line break inside it too.
  ---@param para { lnum: integer, line: string }[]
  ---@return string[]
  local function masked_lines(para)
    local texts = {}
    for i, entry in ipairs(para) do
      texts[i] = entry.line
    end
    local masked = dep.mask_html_comments(dep.mask_code_spans(table.concat(texts, "\n")))
    local out, off = {}, 1
    for i, entry in ipairs(para) do
      out[i] = masked:sub(off, off + #entry.line - 1)
      off = off + #entry.line + 1
    end
    return out
  end

  --- Every env link (`$VAR/...`, `${VAR}/...`, `~/...`) in a buffer's lines
  --- that is a link in the Markdown sense: not inside a code block (fenced or
  --- indented), a code span or an HTML comment, not in a YAML front matter.
  --- Documentation that *shows* a link must not be told its example is broken.
  ---
  --- Code spans and comments are found per paragraph, not per line: a span may
  --- wrap over a line break (hard-wrapped prose does exactly that), and read line
  --- by line the closing backtick would pair with the next one on its line, and
  --- the link between them would be missed or an example in the next span
  --- exposed. (See `each_paragraph` for where a paragraph ends; the lines of a
  --- block quote are one paragraph, so a span that wraps over `>` lines is
  --- followed.)
  ---@param lines string[]
  ---@return LspNvim.EnvLink.Found[]
  function X.scan(lines)
    local found = {} ---@type LspNvim.EnvLink.Found[]
    each_paragraph(lines, function(para)
      for i, text in ipairs(masked_lines(para)) do
        if text:find("[$~]") then
          for _, link in ipairs(dep.links(text)) do
            if dep.is_env_target(link.target) and #found < lim.MAX_SCANNED_LINKS then
              found[#found + 1] =
                { lnum = para[i].lnum, target = link.target, first = link.first, last = link.last }
            end
          end
        end
      end
      return #found >= lim.MAX_SCANNED_LINKS
    end)
    return found
  end

  --- Line `lnum` (1-based) of `lines` as `scan` sees it -- its code spans blanked
  --- out, also the ones that wrap over a line break -- or nil when the line is no
  --- document text: in a fenced code block or a front matter, blank, or too long.
  ---@param lines string[]
  ---@param lnum integer
  ---@return string|nil
  function X.masked_line_at(lines, lnum)
    local result ---@type string|nil
    each_paragraph(lines, function(para)
      if para[#para].lnum + 1 < lnum then
        return false -- an earlier paragraph
      end
      for i, text in ipairs(masked_lines(para)) do
        if para[i].lnum + 1 == lnum then
          result = text
        end
      end
      return true -- the paragraph of `lnum`, or one past it: done
    end)
    return result
  end

  -- ----------------------------------------------------------------------------
  -- Typing a link target
  -- ----------------------------------------------------------------------------

  ---@class LspNvim.EnvLink.Typing
  ---@field text string # The target as typed so far, up to the cursor.
  ---@field start integer # 1-based byte of its first character (after a `<`).
  ---@field angled boolean # Written in `<...>`: blanks are allowed.

  --- The link target being typed at the byte column `col` (1-based: the cursor
  --- sits before that byte): the text from the start of the target up to the
  --- cursor, in `[text](target`, `![alt](target` or `[label]: target`. nil when the
  --- cursor is not in a target, or the target is already closed (`)` or `>`
  --- before it) or has a blank in it (a bare target ends at one).
  ---
  --- Works on one line, like `target_at`.
  ---@param line any
  ---@param col any
  ---@return LspNvim.EnvLink.Typing|nil
  function X.typing_at(line, col)
    -- (The bracket rule below appends up to 3 bytes to ask `target_at`, which
    -- refuses a line over `MAX_LINE_BYTES`: the same limit for every spelling.)
    if type(line) ~= "string" or type(col) ~= "number" or #line + 3 > lim.MAX_LINE_BYTES then
      return nil
    end
    local before = line:sub(1, col - 1)

    local last ---@type integer|nil
    local pos = 1
    while true do
      local at = before:find("](", pos, true)
      if not at then
        break
      end
      last, pos = at, at + 1
    end

    local start ---@type integer|nil
    if last then
      start = last + 2
    else
      -- A reference definition: `[label]: target`.
      start = before:match("^%s*%[[^%]]+%]:%s*()")
    end
    if not start then
      return nil
    end

    local angled = before:byte(start) == 60 -- "<"
    if angled then
      start = start + 1
    end
    local text = before:sub(start)
    if angled then
      if text:find(">", 1, true) then
        return nil
      end
    else
      if text:find("%s") then
        return nil
      end
      local depth = 0
      for c in text:gmatch("[()]") do
        depth = depth + (c == "(" and 1 or -1)
        if depth < 0 then
          return nil -- the `)` that closes the link is before the cursor
        end
      end
    end
    -- An escaped `[`, or a link inside link text, opens nothing: use the rule set
    -- `target_at` goes by, with the target closed so an empty one forms. (A line
    -- with no `[` before the `](` is the continuation of link text that wrapped.)
    if last and before:sub(1, last):find("[", 1, true) then
      local closed = before .. (angled and "x>)" or "x)")
      if dep.target_at(closed, #before) == nil then
        return nil
      end
    end
    return { text = text, start = start, angled = angled }
  end

  --- Is line `lnum` (1-based) of `lines` no document text: inside a fenced or
  --- indented code block, an HTML comment block or a YAML front matter, or a
  --- fence line itself?
  ---@param lines string[]
  ---@param lnum integer
  ---@return boolean
  function X.fenced_at(lines, lnum)
    local front = front_matter_end(lines)
    if lnum <= front then
      return true
    end
    local st = new_blocks()
    local skip = false
    for k = front + 1, lnum do
      skip = block_step(st, lines[k] or "")
    end
    return skip
  end

  X.columns = columns
  X.fence_step = fence_step
  X.unquote = unquote
  X.list_item = list_item
  X.opens_block = opens_block
  return X
end
