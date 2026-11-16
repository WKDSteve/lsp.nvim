---@module 'lsp.tools.deprecated_help.defaults'
--- The defaults of this feature: `M.keymap = "<leader>oh"` (open help for the
--- last detected deprecated symbol in the current buffer), `M.display` and
--- `M.help_pages`.

local M = {}

-- Default mapping (can be overridden via setup opts)
---@type string
M.keymap = "<leader>oh" -- open help for last detected symbol in the current buffer

-- How the help is shown: "hover" (a float, focus stays) or "help" (`:help`)
---@type "hover"|"help"
M.display = "hover"

-- Extra help pages per filetype for the word-under-cursor lookup (`word.lua`):
-- `{ lua = { "luvref" } }`. Set by `word.setup`.
---@type table<string, string[]>
M.help_pages = {}

return M
