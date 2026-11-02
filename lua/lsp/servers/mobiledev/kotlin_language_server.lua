---@module 'lsp.servers.mobiledev.kotlin_language_server'
--- Kotlin Language Server for Android development.
--- Requires JAVA_HOME to be set.

local notify = require("lib.nvim.notify").create("[lsp.servers.kotlin_language_server]")

local M = {}

---Check if kotlin-language-server and Java are available
---@return boolean, string|nil
local function is_kotlin_available()
  if vim.fn.executable("kotlin-language-server") ~= 1 then
    return false, "kotlin-language-server not found"
  end

  local java_home = vim.env.JAVA_HOME
  if not java_home or java_home == "" then
    if vim.fn.executable("java") ~= 1 then
      return false, "JAVA_HOME not set and 'java' not in PATH"
    end
  end

  return true, nil
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  -- Early exit if requirements not met
  local available, err = is_kotlin_available()
  if not available then
    notify.warn(string.format("Kotlin LSP setup skipped: %s", err or "unknown error"))
    return
  end

  require("lsp.servers.define")("kotlin_language_server", shared, opts, {
    cmd = { "kotlin-language-server" },
    filetypes = { "kotlin" },
    root_markers = {
      "settings.gradle",
      "settings.gradle.kts",
      "build.gradle",
      "build.gradle.kts",
      ".git",
    },
    settings = {
      kotlin = {
        compiler = {
          jvm = {
            target = "1.8",
          },
        },
      },
    },
  })
end

return M
