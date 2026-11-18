---@module 'lsp.integrations.lensline'
---@brief lensline.nvim, codelens-style inline info.
---@description
--- Presence reporting only: the core does not touch it and its configuration is
--- a lazy spec, but the health report should be able to answer whether it is
--- installed.
---
---@see lsp.integrations

local M = {}

---@type string
M.plugin = "lensline.nvim"

---@type boolean
M.hard = false

---@type string
M.note = "inline codelens-style info; configured in the config's plugin spec"

---@return boolean
function M.available()
  return (pcall(require, "lensline"))
end

--- Configure lensline. Called from the pack spec's `config`.
---@return boolean ok
function M.configure()
  local ok, lensline = pcall(require, "lensline")
  if not ok then
    return false
  end

  lensline.setup({
    profiles = {
      {
        name = "minimal",
        -- Listed explicitly: a profile without `providers` falls back to
        -- lensline's defaults, which enable `last_author`. That provider runs
        -- `git blame` over the whole file with a synchronous
        -- `vim.fn.systemlist` on every attach -- measured 200-440 ms of
        -- frozen UI per opened file (plus ~65 ms each for `rev-parse` and
        -- `check-ignore`). Blame stays with gitsigns, which runs it async.
        providers = {
          { name = "usages", enabled = true },
          { name = "last_author", enabled = false },
        },
        style = {
          placement = "inline",
          prefix = "",
          -- Only render lenses for the focused function.
          render = "focused",
        },
      },
    },
  })
  return true
end

return M
