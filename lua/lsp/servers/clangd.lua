---@module 'lsp.servers.clangd'
--- clangd via native LSP config/enable.

---@class ClangdServer
local M = {}

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  require("lsp.servers.define")("clangd", shared, opts, {
    -- The real exe, not Mason's .CMD wrapper (see lsp.core.direct_exe).
    cmd = require("lsp.core.direct_exe").cmd(
      "clangd",
      require("lsp.core.direct_exe").mason_glob("clangd", "clangd_*/bin/clangd.exe")
    ),
    filetypes = { "c", "cpp", "objc", "objcpp" },
    root_markers = { "compile_commands.json", ".git" },
  })
end

return M
