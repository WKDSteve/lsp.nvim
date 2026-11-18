---@module 'lsp.tools.eslint_prettier.prettier'
--- Resolves and caches the `prettier` executable (PATH, falling back to
--- Mason's bin dir) -- the one thing `format.lua` needs before it can
--- spawn anything.
local executable = require("lib.nvim.cross.executable")
local is_windows = require("lib.nvim.cross.platform.is_windows")
local M = { prettier_bin = nil }

---@param name string
---@return string|nil
local function resolve_executable(name)
  -- An absolute path, not the bare name: on Windows npm installs the tool as
  -- `<name>.cmd`, which `vim.fn.executable` finds through PATHEXT but libuv's
  -- spawn does not, so the bare name failed with "failed to spawn" every time.
  -- The `.cmd` is asked for first: next to it npm puts an extensionless sh
  -- shim, which `exepath()` prefers (an exact name beats a PATHEXT expansion)
  -- and which Windows cannot start either.
  if is_windows() then
    local launcher = executable.path(name .. ".cmd")
    if launcher then
      return launcher
    end
  end
  return executable.path(name) or executable.mason_bin(name)
end

function M.get_prettier_bin()
  if M.prettier_bin then
    return M.prettier_bin
  end
  M.prettier_bin = resolve_executable("prettier")
  return M.prettier_bin
end

---@param path string
function M.set_prettier_bin(path)
  M.prettier_bin = path
end

return M
