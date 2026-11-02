---@module 'lsp.core.env_links'
---@brief Resolve `$VAR/...`, `${VAR}/...` and `~/...` Markdown link targets.
---@description
--- A Markdown link like `[notes]($REPOS_DIR/WKDBook/Notes/Links.md)` is a path
--- the *user* can follow -- with gopath.nvim's `gP`, or by hand -- but a
--- language server cannot: marksman resolves link targets relative to the
--- document, so it looks for a folder literally named `$REPOS_DIR`. Measured
--- against real marksman, such a link gets **no definition and no hover**, and
--- reports "Link to non-existent document" for a target that exists. The
--- blanket `suppress_missing_doc_links` in `lsp.servers.marksman.config` hid
--- that -- along with every genuinely broken link, everywhere.
---
--- This module is the resolution half of the fix; it has no LSP in it:
---
---   * `resolve(target)`     -- the file a target names, and whether it exists.
---   * `target_at(line, col)`-- the link target under a byte column.
---   * `verdict(message)`    -- what to do with a marksman diagnostic about
---                              such a link (`lsp.servers.marksman.diagnostics_handler`).
---   * `heading_line(...)`   -- the line of a `#fragment` heading in the target.
---
--- Consumers: the diagnostics filter (drop the false alarm, keep the real
--- one) and `lsp.core.env_links_server` (definition, hover, diagnostics, completion).
---
--- ## Resolution order
---
--- 1. **gopath.nvim**, when it is installed and exposes `resolve_text` (its
---    public text API): it owns the env-variable rules -- `$VAR`, `${VAR}`,
---    both separators, the "well-known" directories such as `$NVIM_CONFIG_DIR`
---    that resolve with no real environment variable -- so a link resolves here
---    exactly as `gP` resolves it there, including any config the user set.
--- 2. **Built-in**, otherwise: the roots of lib.nvim's named-roots registry
---    (`$REPOS_DIR`, `$NVIM_CONFIG_DIR` from `stdpath("config")`, the user's and
---    those other plugins registered), then the real environment, and `~`.
---    Enough to work without gopath, and deliberately no more than that -- the
---    moment it grew rules of its own it would start disagreeing with gopath.
---
--- `~` is always handled here: gopath's text API is about env references.
---
---@see lsp.core.env_links_server
---@see lsp.servers.marksman.diagnostics_handler

local M = {}

---@class LspNvim.EnvLink.Resolved
---@field path string # Absolute, forward slashes.
---@field exists boolean|nil # Whether `path` is on disk (a directory counts); nil when it was not looked at (see `opts.stat`).
---@field fragment string|nil # The `#anchor` of the target, without the `#`.
---@field source "gopath"|"builtin"

--- Does this link target start with something only the user's shell could
--- expand: `$VAR`, `${VAR}`, or `~`?
---@param target any
---@return boolean
function M.is_env_target(target)
  if type(target) ~= "string" then
    return false
  end
  return target:match("^%$[%a_{]") ~= nil or target == "~" or target:match("^~[/\\]") ~= nil
end

--- Separate a link target from its `#fragment`, undo percent-encoding, and
--- drop the angle brackets of `<...>` targets.
---@param target string
---@return string path
---@return string|nil fragment
function M.split(target)
  local t = target:gsub("^<(.*)>$", "%1")
  local path, fragment = t:match("^([^#]*)#(.*)$")
  path = path or t
  local ok, decoded = pcall(vim.uri_decode, path)
  return ok and decoded or path, fragment
end

---@internal
---@param base string
---@param rest string
---@return string
local function join(base, rest)
  local joined = (base:gsub("[/\\]+$", "")) .. "/" .. (rest:gsub("\\", "/"))
  return (vim.fs.normalize(joined, { expand_env = false }):gsub("/+$", ""))
end

---@internal
--- The `~` form: `~` and `~/rest`.
---@param path string
---@return string|nil
local function resolve_home(path)
  local rest = path:match("^~[/\\](.*)$")
  if rest == nil and path ~= "~" then
    return nil
  end
  local home = vim.uv.os_homedir()
  if not home or home == "" then
    return nil
  end
  return join(home, rest or "")
end

---@internal
--- The built-in `$VAR` / `${VAR}` resolver: a root of lib.nvim's named-roots
--- registry first (`$REPOS_DIR`, `$NVIM_CONFIG_DIR` with no real variable behind
--- it, the user's and those other plugins registered), any other environment
--- variable after it.
---@param path string
---@return string|nil
local function resolve_builtin(path)
  -- `${VAR}` and `$VAR` are followed by a separator or by nothing. `${VAR}foo`
  -- is the variable's value with `foo` glued on in a shell, not a folder
  -- below it: not something to guess at. (`roots.match` agrees.)
  local _, root, tail = require("lib.nvim.fs.roots").match(path)
  if root then
    local below = (tail or ""):gsub("^[/\\]+", "")
    return join(root, below)
  end

  local name, rest = path:match("^%${([%w_]+)}[/\\](.*)$")
  if not name then
    name, rest = path:match("^%$([%w_]+)[/\\](.*)$")
  end
  if not name then
    name = path:match("^%${([%w_]+)}$") or path:match("^%$([%w_]+)$")
    rest = ""
  end
  if not name then
    return nil
  end

  local base = vim.env[name]
  if type(base) ~= "string" or base == "" then
    return nil
  end
  return join(base, rest or "")
end

--- Set once `require("gopath")` has failed: a missing module makes `require`
--- search every loader on every call (~0.4 ms measured), and this runs per
--- env-link diagnostic on every push and per hover. An already loaded gopath
--- is still found first, so installing one mid-session costs a restart at most.
---@type boolean
local gopath_absent = false

---@internal
---@return table|nil
local function gopath_module()
  local loaded = package.loaded["gopath"]
  if type(loaded) == "table" then
    return loaded
  end
  if gopath_absent then
    return nil
  end
  local ok, mod = pcall(require, "gopath")
  if ok and type(mod) == "table" then
    return mod
  end
  gopath_absent = true
  return nil
end

---@internal
--- The path gopath.nvim resolves an env reference to, or nil when gopath is
--- absent, predates `resolve_text`, does not recognise the text, or raised.
---
--- Only the *path* is taken from gopath. Its `exists` means "is a regular
--- file" (`gopath.util.path.exists`), so a link to a directory would come back
--- `exists = false` -- measured -- and be reported missing. Whether something
--- is on disk, of whatever type, is decided by the caller with `fs_stat`.
---@param path string
---@return string|nil
local function resolve_gopath(path)
  local gopath = gopath_module()
  if not gopath or type(gopath.resolve_text) ~= "function" then
    return nil
  end
  -- gopath reads a wider grammar than a link target has, and the built-in
  -- resolver (which answers when this returns nil) is the reference:
  --   * `${VAR}foo` is the value with `foo` glued on in a shell, not a folder
  --     below it (see `resolve_builtin`), but gopath takes the separator as
  --     optional;
  --   * a long run of blanks (allowed inside `<...>`) makes gopath's location
  --     parser quadratic: about 100 ms per link at 4000 blanks, measured, and
  --     no real path has one.
  if path:match("^%${[%w_]+}[^/\\]") or path:find("%s%s%s%s%s%s%s%s") then
    return nil
  end
  local called, res = pcall(gopath.resolve_text, path)
  if not called or type(res) ~= "table" or type(res.path) ~= "string" or res.kind == "url" then
    return nil
  end
  -- A `:12`, `(3)` or `+4` at the end is a position for gopath, but it may
  -- just as well be the name of the file (`report(1).md`): a link target is
  -- a path as written, so the answer is the built-in resolver's.
  if res.range ~= nil then
    return nil
  end
  return (res.path:gsub("\\", "/"))
end

---@class LspNvim.EnvLink.ResolveOpts
---@field stat? fun(path: string): boolean|nil # Whether `path` is on disk; nil = not looked at. Default: `fs_stat`.

--- Whether this is Windows (a spec sets it to test the network-path rules anywhere).
---@type boolean
M.windows = vim.fn.has("win32") == 1

--- Whether `path` is a Windows network path (`//host/share`, `\\host\share`). Only
--- there does a stat on a host that does not answer block for the OS connect
--- timeout; on POSIX `//data` is an ordinary local path (the same as `/data`).
---@param path string
---@param win? boolean # Default: running on Windows (a spec passes it).
---@return boolean
function M.is_network_path(path, win)
  if win == nil then
    win = M.windows
  end
  return win and (path:find("^//[^/]") ~= nil or path:find("^\\\\") ~= nil)
end

--- Most links `leads_to_network` follows by hand before it gives up.
---@type integer
M.MAX_LINK_HOPS = 8

--- Does `path` lead to a network path through a symbolic link? Every component
--- is read from the root down, never traversed: a link anywhere in the path
--- (`~/nas/notes/x.md` with `nas` a link to a share) is found before a stat
--- would follow it, and a stat that follows one to a share that does not answer
--- blocks Neovim for the OS connect timeout (21 s measured). Link by link, up to
--- `MAX_LINK_HOPS`; the string of `path` alone says nothing about where it leads.
---
--- `known` is an optional memo of the prefixes found not to be links (`false`):
--- hand the same table to every call of one pull and the shared parent
--- directories are read once.
---@param path string
---@param known? table<string, false>
---@return boolean
function M.leads_to_network(path, known)
  path = (path:gsub(string.char(92), "/"))
  if M.is_network_path(path) then
    return true
  end
  local hops, from = 0, 1
  while true do
    local sep = path:find("/", from + 1, true)
    local prefix = sep and path:sub(1, sep - 1) or path
    local target ---@type string|nil
    if prefix ~= "" and not prefix:find("^%a:$") and not (known and known[prefix] == false) then
      target = vim.uv.fs_readlink(prefix)
      if not target and known then
        known[prefix] = false
      end
    end
    if target then
      hops = hops + 1
      if hops > M.MAX_LINK_HOPS then
        return true -- a loop, or a chain this deep: not worth a stat
      end
      target = (target:gsub(string.char(92), "/"))
      if M.is_network_path(target) or target:find("^/%?%?/UNC/") then
        return true
      end
      if not (target:find("^/") or target:find("^%a:")) then
        -- relative to the link's folder (`dirname` of `X:/l` keeps the slash: `X:/`)
        target = ((vim.fs.dirname(prefix) or "."):gsub("/+$", "")) .. "/" .. target
      end
      -- Carry on with the rest of the path below what the link names.
      path = target:gsub("/+$", "") .. (sep and path:sub(sep) or "")
      from = 1
    elseif not sep then
      return false
    else
      from = sep
    end
  end
end

---@internal
--- Whether `path` is on disk, by `fs_stat` -- but not for a network path
--- (`//host/share`, `\\host\share`): a stat on one that does not answer blocks Neovim
--- for the OS connect timeout (21 s measured), and a time budget cannot interrupt
--- a call that is already blocked. nil is "not looked at", the answer for a path
--- nobody asked the disk about; every caller of `resolve` gets it by default
--- (hover and definition, the marksman filter, the diagnostics).
---@param path string
---@return boolean|nil
local function on_disk(path)
  if M.is_network_path(path) or M.leads_to_network(path) then
    return nil
  end
  return vim.uv.fs_stat(path) ~= nil
end

--- Resolve a link target.
---
--- nil when the target is not an env/home reference at all, or names a
--- variable nothing defines -- the caller then leaves the link alone, which
--- is the right answer for "cannot tell". Also nil for a target that decodes
--- to a path holding a control byte (`%00`): no file has one, and a NUL would
--- cut the path short in every call that hands it to the OS.
---@param target string
---@param opts? LspNvim.EnvLink.ResolveOpts
---@return LspNvim.EnvLink.Resolved|nil
function M.resolve(target, opts)
  if not M.is_env_target(target) then
    return nil
  end
  local path, fragment = M.split(target)
  if path:find("[%z\1-\31]") then
    return nil
  end
  local stat = opts and opts.stat or on_disk

  local home = resolve_home(path)
  if home then
    return {
      path = home,
      exists = stat(home),
      fragment = fragment,
      source = "builtin",
    }
  end

  local via = resolve_gopath(path)
  if via then
    return {
      path = via,
      exists = stat(via),
      fragment = fragment,
      source = "gopath",
    }
  end

  local resolved = resolve_builtin(path)
  if not resolved then
    return nil
  end
  return {
    path = resolved,
    exists = stat(resolved),
    fragment = fragment,
    source = "builtin",
  }
end

--- Longest link target or path quoted in a message, in bytes.
---@type integer
M.MAX_QUOTED_BYTES = 200

--- `text` made safe to quote in a message: no control bytes (the link target is
--- whatever the document says, a `<...>` one may hold a tab or an escape), and
--- not longer than `MAX_QUOTED_BYTES`.
---@param text string
---@return string
function M.quoted(text)
  text = text:gsub("%c", "?")
  if #text > M.MAX_QUOTED_BYTES then
    text = text:sub(1, M.MAX_QUOTED_BYTES) .. "..."
  end
  return text
end

--- A resolved path as it may be shown, or nil when it may not: an absolute one
--- below a directory that exists (not the root alone). The path is the variable's value joined with the rest
--- of the target, and a variable can hold anything: `[x]($API_TOKEN/a.md)`
--- resolves to `<the token>/a.md`, which is not a path and must not be put on the
--- screen by a document. A secret is not a directory (and one that happens to
--- start with a slash has no directory that exists), so it is not shown; a
--- path to a file that is not there yet, in a folder that is, is.
---@param path string
---@param stat? fun(path: string): boolean|nil # Whether a path is on disk (default: guarded `fs_stat`).
---@return string|nil
function M.displayable_path(path, stat)
  if not (path:find("^/") or path:find("^%a:/")) then
    return nil
  end
  -- A directory below the root, not the root: `/` and `C:/` always exist, so a
  -- value that is nothing but `/secret` or `C:/secret` would otherwise pass.
  local dir = path:match("^(.*)/[^/]*$")
  if dir == nil or dir:find("^/*$") or dir:find("^%a:/*$") then
    return nil
  end
  if not (stat or on_disk)(dir) then
    return nil
  end
  return M.quoted(path)
end

--- Where a link was looked up, as the tail of a message: ` (resolved to <path>)`,
--- or nothing when the path may not be shown (see `displayable_path`).
---@param path string
---@param stat? fun(path: string): boolean|nil
---@return string
function M.looked_up_at(path, stat)
  local shown = M.displayable_path(path, stat)
  return shown and (" (resolved to " .. shown .. ")") or ""
end

-- ----------------------------------------------------------------------------
-- Link under the cursor
-- ----------------------------------------------------------------------------

--- Longest line `target_at` will scan, in bytes. No hand-written Markdown link
--- sits on a line this long; it caps the work a hover or `gd` does on a
--- minified or generated line of any length.
---@type integer
M.MAX_LINE_BYTES = 20000

--- Longest link target `target_at` will return, in bytes: `PATH_MAX`, and far
--- beyond anything a person types. For a bare inline target it also caps the
--- scan per link on lines such as `[a]($X/[a]($X/...`, where every target
--- would otherwise run to the end of the line. (A `<...>` target is found with
--- one plain `find`, and a reference definition with two anchored patterns,
--- each linear in a line of at most `MAX_LINE_BYTES`: the limit there is the
--- same rule, not a cost bound.)
---@type integer
M.MAX_TARGET_BYTES = 4096

--- Most env links `scan` returns for one buffer. Above this a buffer is a
--- generated file, not a note, and the answer would not be read anyway.
---@type integer
M.MAX_SCANNED_LINKS = 2000

local P = require("lsp.core.env_links.parse")({ limits = M })
M.target_at = P.target_at
M.links = P.links
M.mask_code_spans = P.mask_code_spans
M.mask_html_comments = P.mask_html_comments
local is_space = P.is_space

local B = require("lsp.core.env_links.blocks")({
  limits = M,
  is_env_target = M.is_env_target,
  links = P.links,
  target_at = P.target_at,
  mask_code_spans = P.mask_code_spans,
  mask_html_comments = P.mask_html_comments,
})
M.scan = B.scan
M.masked_line_at = B.masked_line_at
M.typing_at = B.typing_at
M.fenced_at = B.fenced_at
local columns = B.columns
local fence_step = B.fence_step
local unquote = B.unquote
local list_item = B.list_item
local opens_block = B.opens_block

-- ----------------------------------------------------------------------------
-- Diagnostics
-- ----------------------------------------------------------------------------

--- The link target a marksman "non-existent document" diagnostic is about.
---@param message any
---@return string|nil
function M.message_target(message)
  if type(message) ~= "string" then
    return nil
  end
  return message:match("^Link to non%-existent document '(.*)'")
end

--- What to do with a marksman diagnostic, as far as env links are concerned.
---
--- * `"drop"` -- it says the document does not exist, the target is an env
---   link, and the file it resolves to *does* exist: a false alarm.
--- * `"keep"` -- same, but the resolved file is not there: a real broken link,
---   and one that can now be reported with the path it was looked up at.
--- * `nil`    -- not about an env link, or the variable is not defined and
---   nothing can be said; the caller's own rules apply.
---@param message any
---@return "drop"|"keep"|nil verdict
---@return LspNvim.EnvLink.Resolved|nil resolved
function M.verdict(message)
  local target = M.message_target(message)
  if not target or not M.is_env_target(target) then
    return nil, nil
  end
  local resolved = M.resolve(target)
  if not resolved or resolved.exists == nil then
    return nil, nil -- not looked at (a network path): cannot tell
  end
  return resolved.exists and "drop" or "keep", resolved
end

-- ----------------------------------------------------------------------------
-- Target content
-- ----------------------------------------------------------------------------

--- Largest file the content helpers (`heading_line`, `preview`) will read.
---@type integer
M.MAX_READ_BYTES = 2 * 1024 * 1024

--- Longest line `heading_line` will take for a heading, in bytes. Not a limit
--- on the file: a longer line is simply not one. (It is a limit on work, too --
--- see `heading_title`.)
---@type integer
M.MAX_HEADING_BYTES = 2000

--- Longest preview line, in characters.
---@type integer
M.MAX_PREVIEW_LINE_BYTES = 200

--- Extensions of the files whose content is ever read on the strength of a
--- link. A hover previews the top of the target; without this, a document
--- linking `[x]($HOME/.ssh/id_rsa)` or `~/.aws/credentials` would put the first
--- lines of a secret into a hover the moment someone looks at the link. Only
--- documents are read; everything else is still *resolved* and jumped to, just
--- never quoted.
---@type table<string, true>
local TEXT_DOC_EXT = { md = true, markdown = true, mdx = true, txt = true }

---@internal
--- The file `path` really is, when it is a small regular Markdown/text file --
--- one it is fine to read; nil otherwise.
---
--- Every check is made on the file that would be opened, not on how the link
--- spells it: a symlink named `x.md` that points at `~/.ssh/id_rsa` has the
--- extension of a document and the content of a key, and `x%00.md` decodes to
--- a path the OS cuts short at the NUL. So the path is resolved first, and its
--- extension, type and size are what count.
---@param path string
---@return string|nil real
---@return table|nil stat # `vim.uv.fs_stat` of `real`.
local function text_doc(path)
  if path:find("[%z\1-\31]") then
    return nil
  end
  local real = vim.uv.fs_realpath(path)
  if not real then
    return nil
  end
  local ext = real:match("%.(%w+)$")
  if not ext or not TEXT_DOC_EXT[ext:lower()] then
    return nil
  end
  local st = vim.uv.fs_stat(real)
  if not st or st.type ~= "file" or st.size > M.MAX_READ_BYTES then
    return nil
  end
  return real, st
end

local H = require("lsp.core.env_links.headings")({
  max_heading_bytes = function()
    return M.MAX_HEADING_BYTES
  end,
  mask_code_spans = function(text)
    return M.mask_code_spans(text)
  end,
  is_space = is_space,
  columns = columns,
})
local lower = H.lower
local slug = H.slug
local heading_title = H.heading_title
local rtrim = H.rtrim
local split_custom_id = H.split_custom_id
local rendered_title = H.rendered_title
local without_symbols = H.without_symbols
local without_emphasis_underscores = H.without_emphasis_underscores
local is_setext_underline = H.is_setext_underline

---@class LspNvim.EnvLink.HeadingIndex : table<string, integer>

---@class LspNvim.EnvLink.Anchor
---@field anchor string  # The exact GitHub-style anchor (`x`, `x-1`, ...).
---@field line integer   # 0-based line of the heading.
---@field title string   # The heading's text.

---@class LspNvim.EnvLink.IndexCacheEntry
---@field size integer
---@field sec integer
---@field nsec integer
---@field index LspNvim.EnvLink.HeadingIndex
---@field anchors LspNvim.EnvLink.Anchor[]

--- How many heading indexes are kept between calls.
---@type integer
M.INDEX_CACHE_SIZE = 64

---@type table<string, LspNvim.EnvLink.IndexCacheEntry>
local index_cache = {}
---@type string[] # Keys of `index_cache`, oldest first.
local index_cache_order = {}

--- Forget every cached heading index.
---@return nil
function M.clear_cache()
  index_cache = {}
  index_cache_order = {}
end

--- The anchors of the Markdown file at `path`, each with the 0-based line it
--- names: a heading's GitHub-style slug (ATX headings, also in block quotes and
--- list items; setext headings too, at the top level, in block quotes and in list items; a repeated heading `x` is `x`,
--- `x-1`, `x-2`, ..., counted on the anchor GitHub ends up with), its
--- `{#custom-id}`, and the `id`/`name` of an HTML anchor. Headings inside fenced code blocks and a YAML
--- front matter are not headings.
---
--- Besides the exact GitHub anchor a heading is also known by a few lenient
--- spellings (its emoji or its emphasis underscores left in, an image's alt
--- text kept, the title with its `{#id}`): they can only make a link resolve
--- that GitHub would not, never the reverse.
---
--- nil when the file cannot be judged: not Markdown or text, too large, or
--- unreadable. That is "cannot tell", not "no anchors".
---
--- Diagnostics ask for the same few files on every keystroke, so an index is
--- kept (`INDEX_CACHE_SIZE` of them, by the file's real path) for as long as
--- the file's size and modification time stay the same: one `fs_stat` instead of
--- a read and a parse, and the case variants of a path on a case-insensitive
--- file system are one file. The returned table is shared: do not change it.
---@param path string
---@param only_cached? boolean # Answer from the cache or not at all: no read, no parse.
---@return LspNvim.EnvLink.HeadingIndex|nil index
---@return boolean|nil cached # True when it came from the cache: a stat, no read.
function M.heading_index(path, only_cached)
  local real, st = text_doc(path)
  if not real or not st then
    return nil
  end
  local hit = index_cache[real]
  if hit and hit.size == st.size and hit.sec == st.mtime.sec and hit.nsec == st.mtime.nsec then
    return hit.index, true
  end
  if only_cached then
    return nil
  end
  local content = require("lib.nvim.fs.read")(real)
  if not content then
    return nil
  end
  -- Neovim hides a UTF-8 byte order mark; `fs.read` does not, and it would
  -- glue itself to the first line and hide a `# Title` there.
  if content:sub(1, 3) == "\239\187\191" then
    content = content:sub(4)
  end

  local index = {} ---@type LspNvim.EnvLink.HeadingIndex
  local anchors = {} ---@type LspNvim.EnvLink.Anchor[]
  -- The anchors GitHub gives, counted the way github-slugger counts them, and
  -- the lenient spellings a heading is also known by, counted among themselves:
  -- an exact anchor always wins over a lenient one, whatever the order.
  local occ, lenient, locc = {}, {}, {} ---@type table<string, integer>, table<string, integer>, table<string, integer>
  ---@param tbl table<string, integer>
  ---@param key string
  ---@param n integer
  local function add(tbl, key, n)
    if key ~= "" and tbl[key] == nil then
      tbl[key] = n
    end
  end
  --- Register `anchor` the way GitHub numbers it (github-slugger): the first
  --- heading with it gets it bare, later ones `-1`, `-2`, ..., skipping a number
  --- another heading's anchor already took.
  ---@param anchor string
  ---@param n integer
  ---@param tbl table<string, integer>
  ---@param counter table<string, integer>
  local function numbered(anchor, n, tbl, counter)
    if anchor == "" then
      return nil
    end
    local result = anchor
    while counter[result] ~= nil do
      counter[anchor] = counter[anchor] + 1
      result = anchor .. "-" .. counter[anchor]
    end
    counter[result] = 0
    add(tbl, result, n)
    return result
  end
  --- Index one heading: `title` is its source text, `n` its first line.
  ---@param title string
  ---@param n integer
  local function index_title(title, n)
    local text, id = split_custom_id(title)
    -- Not trimmed: a trailing image or tag leaves the blank before it, and that
    -- is the hyphen GitHub keeps (`## Title <img>` is `#title-`).
    local rendered = rendered_title(text)
    if rendered:match("^%s*$") then
      rendered = ""
    end
    local plain = rendered:find("_", 1, true) and without_emphasis_underscores(rendered) or rendered

    -- What GitHub ends up with: emphasis and symbols dropped.
    local exact = slug(without_symbols(plain))
    local registered = numbered(exact, n, index, occ)
    if registered then
      -- The exact anchors in document order, for completion (the index above
      -- also holds custom ids, HTML anchors and lenient spellings).
      anchors[#anchors + 1] = { anchor = registered, line = n, title = rtrim(plain) }
    end

    -- The lenient spellings (an emoji or emphasis left in, an image's alt text
    -- kept, the title with its `{#id}`, any of them trimmed). Each distinct one
    -- once, and none that is the exact one.
    local seen, tried = { [exact] = true }, {}
    ---@param text_ string
    local function spelled(text_)
      if tried[text_] then
        return -- the same text again (an ASCII title without `_` is all of them)
      end
      tried[text_] = true
      local anchor = slug(text_)
      if anchor ~= "" and not seen[anchor] then
        seen[anchor] = true
        numbered(anchor, n, lenient, locc)
      end
    end
    spelled(rtrim(without_symbols(plain)))
    spelled(rendered)
    spelled(rtrim(rendered))
    spelled(plain)
    spelled(without_symbols(rendered))
    if text:find("![", 1, true) then
      local alt = rendered_title(text, true)
      spelled(alt)
      spelled(rtrim(alt))
    end
    if id then
      add(index, lower(id), n)
      -- GitHub has no custom ids: it renders the braces as text.
      local full = rendered_title(title)
      spelled(full)
      spelled(rtrim(full))
    end
  end

  -- A YAML front matter is no document text: `# a comment` in it is not a
  -- heading. Only one that is closed counts, as in `scan`.
  local front_until = -1 ---@type integer # Last 0-based line of the front matter.
  if content:match("^%-%-%-[ \t]*\r?\n") then
    local k = 0
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do
      if k > 0 and (line:match("^%-%-%-%s*$") or line:match("^%.%.%.%s*$")) then
        front_until = k
        break
      end
      k = k + 1
    end
  end

  local fence ---@type LspNvim.EnvLink.Fence|nil
  local skip ---@type boolean
  local para, para_first = {}, 0 ---@type string[], integer # Lines of the paragraph a setext underline would turn into a heading.
  local para_head, para_quote, para_indent = "", 0, 0 ---@type string, integer, integer # Its first line (unquoted), quote depth, list item content column.
  local lists, lists_quote = {}, 0 ---@type integer[], integer # Content columns of the open list items (innermost last), and their quote depth.
  local n = 0
  for line in (content .. "\n"):gmatch("(.-)\r?\n") do
    if n <= front_until then
      fence, skip = nil, true -- YAML is no Markdown: its lines open no fence
    else
      fence, skip = fence_step(fence, line)
    end
    if skip then
      para = {}
    else
      local title = heading_title(line)
      -- A setext heading may sit in a block quote (its underline at the same
      -- depth) or a list item (its underline indented to the item's content).
      local quote, rest = unquote(line)
      local item = list_item(rest)
      if quote ~= lists_quote then
        lists, lists_quote = {}, quote
      end
      if #para > 0 and quote == para_quote and is_setext_underline(rest, para_indent) then
        index_title(table.concat(para, " "), para_first)
        para = {}
      elseif title then
        index_title(title, n)
        para = {}
      elseif #line > M.MAX_HEADING_BYTES or #para >= 8 then
        para = {} -- too long to be a heading: it is not one, and neither is what follows
      elseif item and (#para == 0 or opens_block(rest, para_head)) then
        -- A list item starts a paragraph of its own, inside the item.
        local item_lead, content_col = list_item(rest)
        while #lists > 0 and lists[#lists] > item_lead do
          lists[#lists] = nil
        end
        lists[#lists + 1] = content_col
        local inner = rest:match("^[ \t]*[-*+][ \t]+(.*)$")
          or rest:match("^[ \t]*%d+[.)][ \t]+(.*)$")
        if opens_block(inner) then
          para = {}
        else
          para, para_first, para_head = { rtrim(inner) }, n, rest
          para_quote, para_indent = quote, content_col
        end
      elseif #para > 0 and quote == para_quote and not opens_block(rest, para_head) then
        -- Leading blanks and the trailing ones before a line break are no
        -- part of the title.
        para[#para + 1] = rtrim(rest:sub(rest:match("^%s*()")))
      elseif not opens_block(rest) then
        -- A paragraph of its own sits in the innermost list item whose content
        -- it reaches (a list continuation paragraph); a line left of an item's
        -- content ends the item.
        local lead = columns(rest:match("^[ \t]*"))
        while #lists > 0 and lists[#lists] > lead do
          lists[#lists] = nil
        end
        para, para_first, para_head = { rtrim(rest:sub(rest:match("^%s*()"))) }, n, rest
        para_quote, para_indent = quote, lists[#lists] or 0
      else
        para = {}
      end
      if line:find("<", 1, true) and not fence then
        for _, attr in ipairs({ "id", "name" }) do
          for value in line:gmatch("%s" .. attr .. "%s*=%s*[\"']([^\"']+)[\"']") do
            add(index, lower(value), n)
          end
        end
      end
    end
    n = n + 1
  end

  for key, line_no in pairs(lenient) do
    if index[key] == nil then
      index[key] = line_no
    end
  end

  if hit then
    -- A changed file is indexed again: its old place in the order goes, or the
    -- key would be in the list twice and the eviction would drop the entry just
    -- made (every call after that a miss).
    for k = #index_cache_order, 1, -1 do
      if index_cache_order[k] == real then
        table.remove(index_cache_order, k)
        break
      end
    end
  end
  index_cache[real] =
    { size = st.size, sec = st.mtime.sec, nsec = st.mtime.nsec, index = index, anchors = anchors }
  index_cache_order[#index_cache_order + 1] = real
  while #index_cache_order > M.INDEX_CACHE_SIZE do
    index_cache[table.remove(index_cache_order, 1)] = nil
  end
  return index
end

--- The exact GitHub-style anchors of the Markdown file at `path`, in document
--- order (`x`, `x-1`, `x-2` for a repeated heading), each with its 0-based line
--- and its title. Unlike `heading_index` this holds no custom ids, HTML anchors
--- or lenient spellings: it is what a completion menu offers. nil when the file
--- cannot be judged.
---@param path string
---@return LspNvim.EnvLink.Anchor[]|nil
function M.heading_anchors(path)
  local index = M.heading_index(path)
  if not index then
    return nil
  end
  local real = text_doc(path)
  local hit = real and index_cache[real]
  return hit and hit.index == index and hit.anchors or nil
end

--- The 0-based line `fragment` names in `index`, nil when it names nothing.
--- The fragment is percent-decoded and matched as an anchor, so `#Second-Part`,
--- `#second%20part` and `#second-part` all find "## Second Part".
---@param index LspNvim.EnvLink.HeadingIndex
---@param fragment any
---@return integer|nil
function M.heading_lookup(index, fragment)
  if type(fragment) ~= "string" or fragment == "" then
    return nil
  end
  local ok, decoded = pcall(vim.uri_decode, fragment)
  if not ok then
    decoded = fragment
  end
  return index[slug(decoded)] or index[lower(decoded)]
end

--- The 0-based line of the heading whose anchor is `fragment` in the file at
--- `path`; nil when there is none or the file cannot be read.
---@param path string
---@param fragment string
---@return integer|nil
function M.heading_line(path, fragment)
  local index = M.heading_index(path)
  return index and M.heading_lookup(index, fragment) or nil
end

--- Whether `path` names a Markdown file: the only kind whose anchors are
--- known well enough to say that one is missing.
---@param path string
---@return boolean
function M.is_markdown(path)
  local ext = path:match("%.(%w+)$")
  ext = ext and ext:lower()
  return ext == "md" or ext == "markdown" or ext == "mdx"
end

--- The first `max_lines` lines of the file at `path`, for a hover preview.
---@param path string
---@param max_lines integer
---@return string[]|nil
function M.preview(path, max_lines)
  local real = text_doc(path)
  if not real then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, real, "", max_lines)
  if not ok then
    return nil
  end
  -- One very long line would otherwise become one very long hover.
  for i, line in ipairs(lines) do
    if #line > M.MAX_PREVIEW_LINE_BYTES then
      lines[i] = vim.fn.strcharpart(line, 0, M.MAX_PREVIEW_LINE_BYTES) .. "..."
    end
  end
  return lines
end

return M
