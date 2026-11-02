---@module 'lsp.servers.gopls'
--- Go language server via native LSP config/enable.

---@class GoplsServer
local M = {}

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  require("lsp.servers.define")("gopls", shared, opts, {
    -- The real exe, not Mason's .CMD wrapper (see lsp.core.direct_exe).
    cmd = require("lsp.core.direct_exe").cmd("gopls", {
      require("lsp.core.direct_exe").mason_package("gopls", "gopls.exe"),
    }),
    filetypes = { "go", "gomod", "gosum" },
    root_markers = { "go.work", "go.mod", ".git" },
    settings = {
      gopls = {
        usePlaceholders = true,
        staticcheck = true,
        gofumpt = true,
        analyses = { unusedparams = true, shadow = true },
        memoryMode = "DegradeClosed",
        directoryFilters = { "-**/node_modules", "-**/dist", "-**/.git" },
      },
    },
  })
end

return M
