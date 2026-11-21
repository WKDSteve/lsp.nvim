---@module 'scripts.gen_bindings'
--- Render the keymap tables in docs/BINDINGS.md from the catalogue.
---
---   nvim --headless -l scripts/gen_bindings.lua           # rewrite
---   nvim --headless -l scripts/gen_bindings.lua --check   # verify, write nothing
---
--- The catalogue is the source of truth (roadmap section 8.1: "docs/BINDINGS.md
--- can be generated from this table -- no doc drift"). Everything between the
--- BEGIN/END markers below is replaced; the prose around them is hand-written
--- and left alone.

local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)

local DOC = root .. "/docs/BINDINGS.md"
local BEGIN = "<!-- BEGIN GENERATED KEYMAPS -->"
local END = "<!-- END GENERATED KEYMAPS -->"

local KEYMAPS = require("lsp.config.KEYMAPS")
local DH_DEFAULTS = require("lsp.tools.deprecated_help.defaults")

--- Escape the characters that would break a Markdown table cell.
---@param text string
---@return string
local function cell(text)
  return (text:gsub("|", "\\|"))
end

--- Render one mode value the way `vim.keymap.set` accepts it.
---@param mode string|string[]
---@return string
local function modes(mode)
  if type(mode) == "table" then
    return table.concat(mode, ", ")
  end
  return mode
end

---@type string[]
local out = { BEGIN, "" }

local names = vim.deepcopy(KEYMAPS.presets.default)
table.sort(names)

---@type integer
local keyless = 0
for _, name in ipairs(names) do
  if KEYMAPS.entries[name].lhs == nil then
    keyless = keyless + 1
  end
end

out[#out + 1] = ("The `default` preset covers all %d entries below. `minimal` covers the %d"):format(
  #names,
  #KEYMAPS.presets.minimal
)
out[#out + 1] = "marked in the last column; `none` binds nothing."
if keyless > 0 then
  out[#out + 1] = ("%d %s no default key (lhs `—`): bound only when `keymaps.map.<action>` names one,"):format(
    keyless,
    keyless == 1 and "entry has" or "entries have"
  )
  out[#out + 1] = "under any preset."
end
out[#out + 1] = ""
out[#out + 1] = "| action | lhs | mode | needs | minimal | description |"
out[#out + 1] = "| --- | --- | --- | --- | --- | --- |"

---@type table<string, true>
local in_minimal = {}
for _, name in ipairs(KEYMAPS.presets.minimal) do
  in_minimal[name] = true
end

for _, name in ipairs(names) do
  local spec = KEYMAPS.entries[name]
  out[#out + 1] = ("| `%s` | %s | %s | %s | %s | %s |"):format(
    name,
    spec.lhs and ("`" .. cell(spec.lhs) .. "`") or "—",
    modes(spec.mode),
    spec.requires and ("`" .. spec.requires .. "`") or "—",
    in_minimal[name] and "yes" or "—",
    cell(spec.desc)
  )
end

out[#out + 1] = ""
out[#out + 1] = "which-key group labels:"
out[#out + 1] = ""
out[#out + 1] = "| prefix | label |"
out[#out + 1] = "| --- | --- |"

---@type string[]
local prefixes = vim.tbl_keys(KEYMAPS.groups)
table.sort(prefixes)
for _, prefix in ipairs(prefixes) do
  out[#out + 1] = ("| `%s` | %s |"):format(cell(prefix), KEYMAPS.groups[prefix])
end

-- Keys outside the catalogue, generated too so their default cannot drift
-- from the code. `<leader>oh` is buffer-local (set in every lua_ls buffer by
-- tools.deprecated_help) and its key is part of the diagnostic hint text;
-- the catalogue binds globally, so it stays out on purpose.
out[#out + 1] = ""
out[#out + 1] = "Buffer-local keys outside the catalogue (not affected by `keymaps.*`):"
out[#out + 1] = ""
out[#out + 1] = "| lhs | mode | where | description |"
out[#out + 1] = "| --- | --- | --- | --- |"
out[#out + 1] = ("| `%s` | n | every `lua_ls` buffer, with `tools.deprecated_help.enable` | %s |"):format(
  cell(DH_DEFAULTS.keymap),
  "Help for the deprecated symbol lua_ls reported last; the diagnostic hint names this key. Set `tools.deprecated_help.keymap` to change it, `false` to bind none"
)

out[#out + 1] = ""
out[#out + 1] = END

local generated = table.concat(out, "\n")

local fh = assert(io.open(DOC, "r"))
local current = fh:read("*a")
fh:close()

local s = current:find(BEGIN, 1, true)
local _, e2 = current:find(END, 1, true)
if not (s and e2) then
  io.stderr:write("gen_bindings: markers not found in docs/BINDINGS.md\n")
  vim.cmd("cq 1")
end

local updated = current:sub(1, s - 1) .. generated .. current:sub(e2 + 1)

local check = false
for _, a in ipairs(_G.arg or {}) do
  if a == "--check" then
    check = true
  end
end

if updated == current then
  print("docs/BINDINGS.md is current")
  vim.cmd("cq 0")
end

if check then
  io.stderr:write("gen_bindings: docs/BINDINGS.md is stale -- run without --check\n")
  vim.cmd("cq 1")
end

-- "wb": text mode on Windows would write CRLF into an LF file.
local wh = assert(io.open(DOC, "wb"))
wh:write(updated)
wh:close()
print("docs/BINDINGS.md regenerated")
vim.cmd("cq 0")
