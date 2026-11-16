---@module 'lsp.tools.deprecated_help.word'
--- `:help` for the word under the cursor, through the same float the
--- deprecation hint uses (`help_float`).
---
--- Lookup order:
---
--- 1. the help pages named for the buffer's filetype in `help_pages`
---    (`{ lua = { "luvref" } }`): each entry is a help file on the runtimepath
---    (`doc/<name>`, `.txt` optional) or a path to a help-formatted file. Such a
---    page is searched for the word as a tag, and for a tag that ends in it
---    (`fs_stat` finds `*uv.fs_stat()*`), so a page does not need the exact
---    spelling the code uses;
--- 2. Neovim's help tags on the runtimepath (`help_float.lookup`).
---
--- Each step tries the dotted name under the cursor (`vim.api.nvim_buf_get_lines`)
--- first and then the plain `<cword>` (`nvim_buf_get_lines`).
---
--- `display = "hover"` shows the entry in a float; `"help"` jumps into the
--- match: `:help <tag>` when the runtime help resolves the tag to that file,
--- otherwise the page opened read-only in a split at the tag's line.

local notify = require("lib.nvim.notify").create("[lsp.tools.deprecated_help.word]")
local help_float = require("lsp.tools.deprecated_help.help_float")
local defaults = require("lsp.tools.deprecated_help.defaults")

local M = {}

--- Longest word that is looked up; longer text is not a symbol.
---@type integer
M.MAX_WORD = 200

---@type string
local TAG_DEF = "%*([^%s|*]+)%*"

---@class LspNvim.DeprecatedHelp.Match
---@field lines string[] the help entry
---@field file string the help file that has it
---@field tag string the tag that matched
---@field lnum integer the line of `file` that defines the tag

--- The dotted name under the cursor and the plain `<cword>`, best first,
--- without duplicates or empty strings.
---@return string[]
function M.words_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local words = {}
  local function add(w)
    if type(w) == "string" and w ~= "" and not vim.tbl_contains(words, w) then
      words[#words + 1] = w
    end
  end
  if line:sub(col, col):match("[%w_.:]") then
    local s, e = col, col
    while s > 1 and line:sub(s - 1, s - 1):match("[%w_.:]") do
      s = s - 1
    end
    while e < #line and line:sub(e + 1, e + 1):match("[%w_.:]") do
      e = e + 1
    end
    local dotted = line:sub(s, e):gsub("^[.:]+", ""):gsub("[.:]+$", "")
    add(dotted)
  end
  add(vim.fn.expand("<cword>"))
  return words
end

--- The file a `help_pages` entry names, or nil when there is none.
---@param page string
---@return string|nil
function M.resolve_page(page)
  if type(page) ~= "string" or page == "" then
    return nil
  end
  if page:find("[/\\]") or page:find("^~") then
    local path = vim.fs.normalize(vim.fn.expand(page))
    return vim.fn.filereadable(path) == 1 and path or nil
  end
  local name = page:find("%.%w+$") and page or (page .. ".txt")
  return vim.api.nvim_get_runtime_file("doc/" .. name, false)[1]
end

--- The tags `lines` defines whose name ends in `.word`, `:word` or the same
--- with `()`, in file order.
---@param lines string[]
---@param word string
---@return string[]
local function suffix_tags(lines, word)
  local tail = word:match("[^.:]+$") or word
  local out = {}
  for _, line in ipairs(lines) do
    for tag in line:gmatch(TAG_DEF) do
      local base = tag:gsub("%(%)$", "")
      if
        #base > #tail
        and base:sub(-#tail) == tail
        and base:sub(-#tail - 1, -#tail - 1):match("[.:]")
      then
        out[#out + 1] = tag
      end
    end
  end
  return out
end

--- Search one help page for `word`: as a tag first, then as the end of one.
---@param file string
---@param lines string[]
---@param word string
---@return LspNvim.DeprecatedHelp.Match|nil
function M.search_page(file, lines, word)
  local tags = help_float.candidates(word)
  vim.list_extend(tags, suffix_tags(lines, word))
  for _, tag in ipairs(tags) do
    local entry, lnum = help_float.section(lines, tag)
    if entry and lnum then
      return { lines = entry, file = file, tag = tag, lnum = lnum }
    end
  end
  return nil
end

--- Find the help entry for the first of `words` that has one.
---@param words string[]
---@param filetype string
---@return LspNvim.DeprecatedHelp.Match|nil
function M.find(words, filetype)
  local pages = defaults.help_pages[filetype] or {}
  ---@type table<string, string[]>
  local read = {}
  for _, word in ipairs(words) do
    for _, page in ipairs(pages) do
      local file = M.resolve_page(page)
      if file then
        read[file] = read[file] or vim.fn.readfile(file)
        local match = M.search_page(file, read[file], word)
        if match then
          return match
        end
      end
    end
    local lines, file, tag, lnum = help_float.lookup(word)
    if lines and file and tag and lnum then
      return { lines = lines, file = file, tag = tag, lnum = lnum }
    end
  end
  return nil
end

--- Open the match in a help window at its tag.
---@param match LspNvim.DeprecatedHelp.Match
function M.jump(match)
  -- `:help` is the native jump, but only when it lands in the same file: a
  -- page outside the runtime help has no `doc/tags` entry, and a tag defined
  -- twice would take `:help` to the other definition.
  local via_tags = help_float.find_tags({ match.tag })[match.tag]
  if via_tags and vim.fs.normalize(via_tags) == vim.fs.normalize(match.file) then
    if pcall(vim.api.nvim_cmd, { cmd = "help", args = { match.tag } }, {}) then
      return
    end
  end
  -- `fnameescape`: a page is any path the config names, and `%`, `#` or a
  -- space in it would otherwise be expanded or split by `:split`.
  vim.cmd("split " .. vim.fn.fnameescape(match.file))
  vim.bo.readonly = true
  vim.bo.modifiable = false
  vim.bo.filetype = "help"
  -- The file may have changed since it was read; land on its last line then.
  local last = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.min(match.lnum, last), 0 })
  vim.cmd("normal! zt")
end

--- Show the help for `word`, or for the word under the cursor when `word` is
--- nil or empty.
---@param word? string
---@param opts? { display?: "hover"|"help" }
---@return boolean shown
function M.show(word, opts)
  opts = opts or {}
  local words
  if type(word) == "string" and word ~= "" then
    words = { word }
  else
    words = M.words_under_cursor()
  end
  if #words == 0 then
    notify.info("No word under the cursor to look up.")
    return false
  end
  for _, w in ipairs(words) do
    if #w > M.MAX_WORD or w:find("%c") then
      notify.warn("Not a word to look up: " .. w:sub(1, 80):gsub("%c", "?"))
      return false
    end
  end

  local match = M.find(words, vim.bo.filetype)
  if not match then
    notify.info("No help found for: " .. table.concat(words, ", "))
    return false
  end
  if (opts.display or defaults.display) == "help" then
    M.jump(match)
  else
    help_float.open(match.lines)
  end
  return true
end

--- Apply `word_keymap` and `help_pages`. A wrong value warns and degrades to
--- the default (no key, no extra pages).
---@param opts { word_keymap?: string|false, help_pages?: table<string, string[]> }|nil
function M.setup(opts)
  opts = opts or {}

  local pages = opts.help_pages
  if pages == nil then
    defaults.help_pages = {}
  elseif type(pages) ~= "table" then
    notify.warn("help_pages: expected a table of filetype = { pages }, ignoring it")
    defaults.help_pages = {}
  else
    local clean = {}
    for ft, list in pairs(pages) do
      if type(ft) == "string" and type(list) == "table" then
        clean[ft] = vim.tbl_filter(function(p)
          return type(p) == "string" and p ~= ""
        end, list)
      else
        notify.warn(
          ("help_pages: ignoring entry %q, expected filetype = { pages }"):format(tostring(ft))
        )
      end
    end
    defaults.help_pages = clean
  end

  local lhs = opts.word_keymap
  if lhs ~= nil and lhs ~= false and (type(lhs) ~= "string" or lhs == "") then
    notify.warn("word_keymap: expected a key or false, binding nothing")
    lhs = false
  end
  if lhs then
    vim.keymap.set("n", lhs, function()
      M.show()
    end, { silent = true, desc = "LSP: Help for the word under the cursor" })
  end
end

return M
