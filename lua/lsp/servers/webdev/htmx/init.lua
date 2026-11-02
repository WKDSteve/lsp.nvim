---@module 'lsp.servers.webdev.htmx'
--- HTMX language server, for HTMX attributes.

local notify = require("lib.nvim.notify").create("[lsp.servers.webdev.htmx_lsp]")
local executable = require("lib.nvim.cross.executable")

local M = {}

---Find htmx-lsp executable
---@return string|nil
local function find_htmx_lsp()
  return executable.path("htmx-lsp") or executable.mason_bin("htmx-lsp")
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
--- `filter_stderr` is gone with the filter it gated: nothing read it once the
--- unreachable attempt was removed, and an option nothing reads is a promise
--- the module does not keep. It returns when there is a mechanism behind it.
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  local htmx_cmd = find_htmx_lsp()
  if not htmx_cmd then
    notify.info("htmx-lsp not found; skipping HTMX LSP setup")
    return
  end

  -- htmx-lsp writes JSON logs to stderr, which Neovim records as [ERROR].
  --
  -- There used to be an attempt at filtering them here: a `handlers` table with
  -- a `stderr` entry, built and then never passed anywhere -- next to a note
  -- saying the filtering did not work. It could not have: `handlers` maps LSP
  -- *methods* to response handlers, and stderr never goes through it. Neovim
  -- reads the server's stderr itself and there is no client-config hook for it,
  -- so filtering would mean wrapping `cmd` in a process that does the filtering
  -- before Neovim ever sees the stream.
  --
  -- Removed rather than kept as a record: dead code that cannot work reads like
  -- code that does. The finding is in the roadmap (B14), and
  -- `htmx/filter_logs.lua` still holds the JSON filter for whoever builds the
  -- mechanism that could use it.

  require("lsp.servers.define")("htmx", shared, opts, {
    cmd = { htmx_cmd },
    filetypes = { "html", "astro", "htmldjango", "eruby" },
    root_markers = { ".git", "package.json" },
    -- handlers = handlers,  -- Uncomment to enable stderr filtering
  })
end

return M
