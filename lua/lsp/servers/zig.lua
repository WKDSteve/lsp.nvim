---@module 'lsp.servers.zig'
--- zls via native LSP config/enable (Neovim ≥ 0.11).

---@class ZigServer
local M = {}

--- The name this module registers its config under (`lsp.config("zls", ...)`); the registry enables this one.
M.lsp_name = "zls"

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  require("lsp.servers.define")("zls", shared, opts, {
    -- The real exe, not Mason's .CMD wrapper (see lsp.core.direct_exe).
    cmd = require("lsp.core.direct_exe").cmd("zls", {
      require("lsp.core.direct_exe").mason_package("zls", "zls.exe"),
    }),
    filetypes = { "zig", "zir" },
    root_markers = { "build.zig", "zls.json", ".git" },
  })
end

return M
