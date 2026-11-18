---@module 'lsp.tools.eslint_prettier.eslint'
--- eslint utilities and bin resolution
local executable = require("lib.nvim.cross.executable")
local is_windows = require("lib.nvim.cross.platform.is_windows")

local M = {
  eslint_bin = nil, -- resolved executable (string)
}

--- Try to resolve executable by name, then mason bin folder, add .cmd on Windows.
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

function M.get_eslint_bin()
  if M.eslint_bin then
    return M.eslint_bin
  end
  M.eslint_bin = resolve_executable("eslint_d")
  return M.eslint_bin
end

---@param path string
function M.set_eslint_bin(path)
  M.eslint_bin = path
end

return M
