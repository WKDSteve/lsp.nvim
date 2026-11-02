-- TESTS/support/stub_server.lua -- an in-process language server for the test sheets (TESTS/sheets/) and the
-- terminal specs (TESTS/pty/): `cmd` is a Lua function, so no process and no install, on Windows and Linux.
--
-- Loaded INSIDE a child editor (`dofile(<root>/TESTS/support/stub_server.lua)`): sheets are data and cannot
-- require anything while they are read.
--
--   local S = dofile(root .. "/TESTS/support/stub_server.lua")
--   S.start({ name = "stub", bufnr = 0, root = dir, capabilities = {...}, handlers = { ["method"] = function(params, uri) ... end } })
--
-- A handler returns the result of its request (nil = null). The ready-made kits below build the answers a
-- real server would give for a small fixed document (see `S.TS`).

local M = {}

---The `cmd` function of a stub server (for `vim.lsp.config(name, { cmd = ... })` and `vim.lsp.start`).
---@param opts { name: string, capabilities?: table, handlers?: table<string, fun(params: table): any> }
---@return fun(dispatchers: table): table
function M.cmd(opts)
  local handlers = opts.handlers or {}
  return function(dispatchers)
    local closing, next_id = false, 0
    local srv = {}
    function srv.request(method, params, callback)
      next_id = next_id + 1
      local id = next_id
      if method == "initialize" then
        callback(nil, { capabilities = opts.capabilities or {}, serverInfo = { name = opts.name } })
      elseif method == "shutdown" then
        callback(nil, nil)
      else
        local h = handlers[method]
        local ok, res = true, nil
        if h then
          ok, res = pcall(h, params)
        end
        vim.schedule(function()
          if ok then
            callback(nil, res)
          else
            callback({ code = -32603, message = tostring(res) }, nil)
          end
        end)
      end
      return true, id
    end
    function srv.notify(method)
      if method == "exit" then
        closing = true
        vim.schedule(function()
          dispatchers.on_exit(0, 0)
        end)
      end
      return true
    end
    function srv.is_closing()
      return closing
    end
    function srv.terminate()
      if not closing then
        closing = true
        vim.schedule(function()
          dispatchers.on_exit(0, 15)
        end)
      end
    end
    return srv
  end
end

---Start the stub server and attach it to `opts.bufnr`.
---@param opts { name: string, bufnr?: integer, root?: string, capabilities?: table, handlers?: table<string, fun(params: table): any> }
---@return integer|nil client_id
function M.start(opts)
  return vim.lsp.start({
    name = opts.name,
    cmd = M.cmd(opts),
    root_dir = opts.root or vim.fn.getcwd(),
  }, { bufnr = opts.bufnr or 0, attach = true })
end

---@param line integer
---@param c1 integer
---@param c2 integer
---@return table
local function range(line, c1, c2)
  return {
    start = { line = line, character = c1 },
    ["end"] = { line = line, character = c2 },
  }
end
M.range = range

---The code actions of the A1/A2 checks: a quick fix whenever asked, and "Extract function" only for a
---selection that spans several lines (as tsserver offers it).
---@param uri string
---@param params table codeAction params
---@return table[]
function M.code_actions(uri, params)
  local list = {
    {
      title = "Add missing import",
      kind = "quickfix",
      edit = {
        changes = {
          [uri] = { { range = range(0, 0, 0), newText = "import { added } from 'x';\n" } },
        },
      },
    },
  }
  local r = params.range
  if r and r["end"].line > r.start.line then
    list[#list + 1] = {
      title = "Extract function",
      kind = "refactor.extract.function",
      edit = {
        changes = { [uri] = { { range = range(r.start.line, 0, 0), newText = "// extracted\n" } } },
      },
    }
  end
  return list
end

return M
