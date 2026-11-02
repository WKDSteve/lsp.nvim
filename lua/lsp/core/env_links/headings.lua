---@module 'lsp.core.env_links.headings'
---@brief Heading text helpers of `lsp.core.env_links`: the GitHub-style slugger and its inputs.
---@description
--- Pure string functions with no I/O: lowercasing, entity decoding, link and
--- emphasis stripping, the symbol fold and the setext-underline test. They were
--- the middle third of `env_links.lua` and are split out so they can be read
--- (and specified) on their own. `env_links` keeps the heading *index* (file
--- reading, caching, duplicate numbering) and re-exports nothing from here.
---
--- The module returns a builder, not a table, because three helpers live in
--- `env_links` itself and must not be required back (a cycle): the builder
--- takes them as `dep`.
---
---@see lsp.core.env_links

---@class LspNvim.EnvLink.HeadingDeps
---@field max_heading_bytes fun(): integer # `env_links.MAX_HEADING_BYTES`, read at call time (tests lower it).
---@field mask_code_spans fun(text: string): string
---@field is_space fun(b: integer): boolean
---@field columns fun(s: string): integer

---@param dep LspNvim.EnvLink.HeadingDeps
---@return table
return function(dep)
  local is_space = dep.is_space
  local columns = dep.columns

  ---@internal
  --- Lowercase `s`, multibyte-aware. A NUL is dropped first: `vim.fn.tolower`
  --- raises on one (E976), and the text comes from a link fragment or from a file
  --- this module does not control.
  ---@param s string
  ---@return string
  local function lower(s)
    return vim.fn.tolower((s:gsub("%z", "")))
  end

  ---@internal
  --- The GitHub-style anchor of a heading: lowercase, punctuation dropped, spaces
  --- to hyphens. Lowercasing is multibyte-aware (`Ü` -> `ü`, which `string.lower`
  --- would leave alone) and non-ASCII bytes are kept -- both are what keep
  --- `Übersicht` and friends working in a German document.
  ---
  --- JavaScript's `toLowerCase`, which GitHub's slugger uses, differs from Vim's
  --- in two places, so both spellings are folded to one: `İ` becomes `i` plus a
  --- combining dot (U+0307), and a capital sigma at the end of a word becomes
  --- `ς` where Vim has `σ`. The same fold runs on the fragment of a link, so
  --- whichever form is written finds the heading.
  ---@param title string
  ---@return string
  local function slug(title)
    local s = lower(title):gsub("[^%w%s%-_\128-\255]", "")
    s = s:gsub("\204\135", ""):gsub("\207\130", "\207\131")
    return (s:gsub("%s", "-"))
  end

  ---@internal
  --- Where a heading's title starts in `line` after the container markers (block
  --- quotes and list markers, which may nest), and that the line is a heading at
  --- all: 0-3 spaces, one to six `#`, a blank. nil for any other line.
  ---
  --- The trailing spaces and closing `#`s are stripped by walking back from the
  --- end. The obvious `^#+%s+(.-)%s*#*%s*$` is cubic on a line with a long run
  --- of spaces inside it (measured: 0.5 s at 1000 bytes, 4.3 s at 2000), and the
  --- line comes from a file this module does not control.
  ---@param line string
  ---@return string|nil
  local function heading_title(line)
    if #line > dep.max_heading_bytes() or not line:find("#", 1, true) then
      return nil -- the cheap check keeps the container walk off ordinary lines
    end
    -- A heading may sit in a block quote or a list item, and GitHub gives it an
    -- anchor there too. Walked by position, bounded in depth.
    local pos = 1
    for _ = 1, 8 do
      local _, e = line:find("^%s*>%s?", pos)
      if not e then
        _, e = line:find("^%s*[-*+]%s+", pos)
      end
      if not e then
        _, e = line:find("^%s*%d%d?%d?%d?%d?%d?%d?%d?%d?[.)]%s+", pos)
      end
      if not e then
        break
      end
      pos = e + 1
    end
    local hashes, rest = line:match("^ ? ? ?(#+)%s+(.*)$", pos)
    if not hashes or #hashes > 6 then
      return nil -- seven `#` are a paragraph, not a heading
    end
    local e = #rest
    while is_space(rest:byte(e)) do
      e = e - 1
    end
    while e > 0 and rest:byte(e) == 35 do -- "#"
      e = e - 1
    end
    while is_space(rest:byte(e)) do
      e = e - 1
    end
    return rest:sub(1, e)
  end

  ---@internal
  --- `s` without trailing whitespace, by walking back from the end (see
  --- `heading_title` for why not a pattern).
  ---@param s string
  ---@return string
  local function rtrim(s)
    local e = #s
    while is_space(s:byte(e)) do
      e = e - 1
    end
    return s:sub(1, e)
  end

  ---@internal
  --- The `{#custom-id}` a heading may end with, and the title without it.
  --- (Kramdown, pandoc, Docusaurus.) Found by looking for the last `{#`, not by a
  --- pattern with a lazy prefix, which is quadratic on a long title.
  ---@param title string
  ---@return string title
  ---@return string|nil id
  local function split_custom_id(title)
    local at ---@type integer|nil
    local from = 1
    while true do
      local p = title:find("{#", from, true)
      if not p then
        break
      end
      at, from = p, p + 1
    end
    if not at then
      return title, nil
    end
    local id = title:sub(at + 2):match("^([%w_%-%.:]+)}%s*$")
    if not id then
      return title, nil
    end
    return rtrim(title:sub(1, at - 1)), id
  end

  ---@internal
  --- Named character references a heading is likely to hold, as code points.
  --- Unknown names stay as written.
  ---@type table<string, integer>
  local NAMED_ENTITIES = {
    amp = 0x26,
    lt = 0x3C,
    gt = 0x3E,
    quot = 0x22,
    apos = 0x27,
    nbsp = 0xA0,
    iexcl = 0xA1,
    cent = 0xA2,
    pound = 0xA3,
    yen = 0xA5,
    sect = 0xA7,
    copy = 0xA9,
    laquo = 0xAB,
    reg = 0xAE,
    deg = 0xB0,
    plusmn = 0xB1,
    para = 0xB6,
    middot = 0xB7,
    raquo = 0xBB,
    frac12 = 0xBD,
    times = 0xD7,
    Auml = 0xC4,
    Ouml = 0xD6,
    Uuml = 0xDC,
    szlig = 0xDF,
    agrave = 0xE0,
    aacute = 0xE1,
    auml = 0xE4,
    ccedil = 0xE7,
    egrave = 0xE8,
    eacute = 0xE9,
    ntilde = 0xF1,
    ouml = 0xF6,
    uuml = 0xFC,
    ndash = 0x2013,
    mdash = 0x2014,
    bull = 0x2022,
    hellip = 0x2026,
    euro = 0x20AC,
    trade = 0x2122,
    larr = 0x2190,
    rarr = 0x2192,
    hearts = 0x2665,
  }

  ---@internal
  --- `s` with `&name;`, `&#N;` and `&#xH;` decoded, as a renderer reads a heading
  --- before it computes the anchor (`## Q&amp;A` is `#qa`, not `#qampa`).
  --- Numeric references to 0, above U+10FFFF or to a surrogate are U+FFFD.
  ---@param s string
  ---@return string
  local function decode_entities(s)
    if not s:find("&", 1, true) then
      return s
    end
    return (
      s:gsub("&(#?%w+);", function(ref)
        local named = NAMED_ENTITIES[ref]
        if named then
          return vim.fn.nr2char(named)
        end
        local cp
        local hex = ref:match("^#[xX](%x+)$")
        if hex and #hex <= 6 then
          cp = tonumber(hex, 16)
        else
          local dec = ref:match("^#(%d+)$")
          cp = dec and #dec <= 7 and tonumber(dec) or nil
        end
        if not cp then
          return nil -- not a reference: keep as written
        end
        if cp == 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
          cp = 0xFFFD
        end
        return vim.fn.nr2char(cp)
      end)
    )
  end

  ---@internal
  --- The `)` that ends the destination of a link whose text closed at `from - 2`:
  --- parentheses inside it balance (`[a](https://x/Foo_(bar))`), a backslash
  --- escapes the next byte. nil when none closes it.
  ---@param shown string
  ---@param from integer # First byte after the `(`.
  ---@return integer|nil
  local function destination_end(shown, from)
    local depth, j = 0, from
    while true do
      local c = shown:find("[()" .. string.char(92) .. "]", j)
      if not c then
        return nil
      end
      local b = shown:byte(c)
      if b == 92 then
        j = c + 2
      elseif b == 40 then
        depth = depth + 1
        j = c + 1
      elseif depth == 0 then
        return c
      else
        depth = depth - 1
        j = c + 1
      end
    end
  end

  ---@internal
  --- One rewriting pass over a title: `[text](url)` becomes its text and
  --- `![alt](url)` its alt text (`keep_alt`) or nothing -- an `<img>` has no text
  --- in the rendered heading, so GitHub's anchor has none of it. A single
  --- left-to-right sweep over the brackets with a stack, so `[a [b] c](u)` pairs
  --- the outer brackets: when no closing `)` is left, none will be found later
  --- either, so the sweep stops instead of searching again from every opener.
  --- What is inside a code span is literal and is left alone (the sweep looks at
  --- a masked copy, and cuts the real title at the same offsets).
  ---@param title string
  ---@param keep_alt boolean
  ---@return string
  local function strip_links(title, keep_alt)
    local shown = dep.mask_code_spans(title)
    local out, piece = {}, 1
    local opens, n = {}, 0 ---@type integer[], integer
    local i = 1
    while true do
      local k = shown:find("[%[%]" .. string.char(92) .. "]", i)
      if not k then
        break
      end
      i = k + 1
      local c = shown:byte(k)
      if c == 92 then -- a backslash escapes the next byte
        i = k + 2
      elseif c == 91 then -- "["
        n = n + 1
        opens[n] = k
      elseif n > 0 then -- "]"
        local open = opens[n]
        n = n - 1
        if shown:byte(k + 1) == 40 then -- "]("
          local close = destination_end(shown, k + 2)
          if not close then
            break
          end
          local image = open > 1 and shown:byte(open - 1) == 33 -- "!"
          local from = image and open - 1 or open
          if from >= piece then
            out[#out + 1] = title:sub(piece, from - 1)
            if not image or keep_alt then
              out[#out + 1] = title:sub(open + 1, k - 1)
            end
            piece = close + 1
          end
          i = close + 1
        end
      end
    end
    out[#out + 1] = title:sub(piece)
    return table.concat(out)
  end

  ---@internal
  --- A title as it reads once rendered, as far as the anchor is concerned: links
  --- and images rewritten (a badge, `[![ci](img)](url)`, takes a second pass, and
  --- a third is the most any real title needs), HTML tags gone and autolinks
  --- (`<https://x.org>`) unwrapped to their text, character references decoded.
  --- Text in a code span is literal and stays as it is, entities included.
  ---@param title string
  ---@param keep_alt? boolean # Keep the alt text of an image (default: drop it).
  ---@return string
  local function rendered_title(title, keep_alt)
    for _ = 1, 3 do
      if not title:find("](", 1, true) then
        break
      end
      local before = title
      title = strip_links(title, keep_alt == true)
      if title == before then
        break
      end
    end

    if title:find("<", 1, true) then
      local shown = dep.mask_code_spans(title)
      local out, piece = {}, 1
      local i = 1
      while true do
        local k = shown:find("<", i, true)
        if not k then
          break
        end
        local auto = shown:match("^<(%a[%w+.-]*:[^%s<>]*)>", k)
          or shown:match("^<([%w._%%+-]+@[%w.-]+)>", k)
        if shown:sub(k, k + 3) == "<!--" then
          local close = shown:find("-->", k + 4, true)
          if not close then
            break
          end
          out[#out + 1] = title:sub(piece, k - 1)
          piece = close + 3
          i = piece
        elseif auto then
          out[#out + 1] = title:sub(piece, k - 1)
          out[#out + 1] = title:sub(k + 1, k + #auto)
          piece = k + #auto + 2
          i = piece
        elseif shown:find("^/?%a[%w:-]*[%s/>]", k + 1) then -- `<T, E>` is text, not a tag
          local close = shown:find(">", k, true)
          if not close then
            break
          end
          out[#out + 1] = title:sub(piece, k - 1)
          piece = close + 1
          i = close + 1
        else
          i = k + 1
        end
      end
      out[#out + 1] = title:sub(piece)
      title = table.concat(out)
    end

    if not title:find("&", 1, true) then
      return title
    end
    -- References are decoded outside code spans only: a span's text is literal.
    local shown = dep.mask_code_spans(title)
    local out, pos = {}, 1
    while true do
      local s_, e_ = title:find("&#?%w+;", pos)
      if not s_ then
        break
      end
      out[#out + 1] = title:sub(pos, s_ - 1)
      local ref = title:sub(s_, e_)
      out[#out + 1] = shown:byte(s_) == 32 and ref or decode_entities(ref)
      pos = e_ + 1
    end
    out[#out + 1] = title:sub(pos)
    return table.concat(out)
  end

  ---@internal
  --- Ranges (`{ first, last }`, sorted) of characters GitHub drops from an anchor
  --- but `slug` cannot tell from a letter in another script: Latin-1 symbols,
  --- general punctuation, arrows, math and dingbats, CJK and full-width
  --- punctuation, Arabic and Devanagari punctuation, variation selectors.
  ---@type integer[][]
  local SYMBOL_RANGES = {
    { 0xA0, 0xBF },
    { 0xD7, 0xD7 },
    { 0xF7, 0xF7 },
    { 0x60C, 0x60D },
    { 0x61B, 0x61B },
    { 0x61E, 0x61F },
    { 0x66A, 0x66D },
    { 0x6D4, 0x6D4 },
    { 0x964, 0x965 },
    { 0x2000, 0x2BFF },
    { 0x3000, 0x303F },
    { 0xFE00, 0xFE0F },
    { 0xFF01, 0xFF0F },
    { 0xFF1A, 0xFF20 },
    { 0xFF3B, 0xFF40 },
    { 0xFF5B, 0xFF65 },
  }

  ---@internal
  --- Is the code point `cp` one GitHub drops from an anchor?
  ---@param cp integer
  ---@return boolean
  local function is_symbol(cp)
    if cp >= 0x1F000 then
      return true
    end
    for _, range in ipairs(SYMBOL_RANGES) do
      if cp < range[1] then
        return false
      elseif cp <= range[2] then
        return true
      end
    end
    return false
  end

  ---@internal
  --- `s` without symbols and emoji, which GitHub drops from an anchor but
  --- `slug` cannot tell from a letter in another script. Only ever used for an
  --- *additional* key (`## 🚀 Features` is `#-features` on GitHub), so a wrong
  --- guess here makes a link resolve that should not, never the reverse.
  ---@param s string
  ---@return string
  local function without_symbols(s)
    if not s:find("[\128-\255]") then
      return s -- plain ASCII has none, and this runs on every heading
    end
    local ok, out = pcall(function()
      local starts = vim.str_utf_pos(s)
      local kept = {}
      for k, from in ipairs(starts) do
        local char = s:sub(from, (starts[k + 1] or #s + 1) - 1)
        if #char == 1 or not is_symbol(vim.fn.char2nr(char)) then
          kept[#kept + 1] = char
        end
      end
      return table.concat(kept)
    end)
    return ok and out or s
  end

  ---@internal
  --- Is the byte `c` part of a word: alphanumeric, or of a multibyte character?
  ---@param c integer|nil
  ---@return boolean
  local function word_byte(c)
    return c ~= nil
      and (c >= 128 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122))
  end

  ---@internal
  --- `s` without the underscores that read as emphasis (`_x_`, `__x__`, `a _b_
  --- c`): GitHub renders them as <em>/<strong> and builds the anchor from the
  --- text, so they are not in it. An underscore run between two alphanumerics
  --- (`snake_case`) is literal and stays. Only ever used for an *additional* key,
  --- like `without_symbols`. One pass over whole runs: a run is judged by the
  --- bytes on its two sides (removing a run never joins two words), and a
  --- pattern that restarts at every underscore of a run is quadratic.
  ---@param s string
  ---@return string
  local function without_emphasis_underscores(s)
    return (
      s:gsub("()(_+)()", function(p, run, q)
        if word_byte(s:byte(p - 1)) and word_byte(s:byte(q)) then
          return run
        end
        return ""
      end)
    )
  end

  ---@internal
  --- Is `rest` (a line without its quote prefix) a setext underline (`===` or
  --- `---`) for a paragraph in a list item whose content starts at column
  --- `indent` (0: none): at least `indent` and at most `indent + 3` blanks before?
  ---@param rest string
  ---@param indent integer
  ---@return boolean
  local function is_setext_underline(rest, indent)
    local lead, mark = rest:match("^([ \t]*)(.*)$")
    local cols = columns(lead)
    if cols < indent or cols > indent + 3 then
      return false
    end
    return mark:match("^=+%s*$") ~= nil or mark:match("^%-+%s*$") ~= nil
  end

  return {
    lower = lower,
    slug = slug,
    heading_title = heading_title,
    rtrim = rtrim,
    split_custom_id = split_custom_id,
    rendered_title = rendered_title,
    without_symbols = without_symbols,
    without_emphasis_underscores = without_emphasis_underscores,
    is_setext_underline = is_setext_underline,
  }
end
