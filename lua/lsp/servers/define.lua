---@module 'lsp.servers.define'
---@brief Register one server config and enable it: the skeleton every server module shares.
---@description
--- A server module is data (cmd, filetypes, root markers, settings) wrapped in
--- the same few lines: skip on a Neovim without `vim.lsp.config`, fill in the
--- shared `capabilities` / `on_attach` / `on_init`, and enable the server
--- unless the registry asked for `enable = false` (it enables by name itself
--- afterwards). That wrapping lives here once.
---
--- A key the module sets in its own `spec` wins over the shared value, so a
--- server that needs its own `on_attach` keeps it.
---
---@see lsp.core.registry

---@class Lsp.Servers.Shared
---@field capabilities? table
---@field on_attach? fun(client: vim.lsp.Client, bufnr: integer)
---@field on_init? fun(client: vim.lsp.Client, init_result: table): boolean?

---@param name string name the config is registered (and enabled) under
---@param shared Lsp.Servers.Shared|nil
---@param opts { enable?: boolean }|nil
---@param spec table the server's own config (cmd, filetypes, root_markers, settings, ...)
---@return nil
return function(name, shared, opts, spec)
  shared = shared or {}
  opts = opts or {}
  if type(vim.lsp.config) ~= "table" then
    return
  end
  vim.lsp.config(
    name,
    vim.tbl_extend("keep", spec, {
      capabilities = shared.capabilities,
      on_attach = shared.on_attach,
      on_init = shared.on_init,
    })
  )
  if opts.enable ~= false then
    pcall(vim.lsp.enable, name)
  end
end
