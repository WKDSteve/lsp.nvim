-- TESTS/support/stdio_server.lua -- a language server as a real process, for the feature sheets that measure what
-- starting one costs (`testing perf`): `nvim -l TESTS/support/stdio_server.lua` speaks LSP over stdin/stdout.
-- It answers `initialize` (documentSymbolProvider, hoverProvider), `textDocument/documentSymbol` (one function
-- `stdio_symbol` on line 0), `textDocument/hover` and `shutdown`, ends on `exit` or when stdin closes, and
-- ignores every notification. The in-process stubs (TESTS/support/stub_server.lua) start no process, so they
-- cannot show the cost of a server start; this one has no dependency but the editor itself, so it runs on CI too.
-- luacheck: globals vim

local uv = vim.uv
local stdin = assert(uv.new_pipe(false))
local stdout = assert(uv.new_pipe(false))
stdin:open(0)
stdout:open(1)

local function send(msg)
  local body = vim.json.encode(msg)
  stdout:write(("Content-Length: %d\r\n\r\n%s"):format(#body, body))
end

local done = false

local function finish()
  if done then
    return
  end
  done = true
  stdin:read_stop()
  stdin:close()
  stdout:shutdown(function()
    stdout:close()
  end)
end

local handlers = {
  initialize = function()
    return {
      capabilities = { documentSymbolProvider = true, hoverProvider = true, textDocumentSync = 1 },
      serverInfo = { name = "stdio_server" },
    }
  end,
  ["textDocument/documentSymbol"] = function()
    local range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 20 } }
    return { { name = "stdio_symbol", kind = 12, range = range, selectionRange = range } }
  end,
  ["textDocument/hover"] = function()
    return { contents = { kind = "plaintext", value = "stdio_server hover" } }
  end,
  shutdown = function()
    return vim.NIL
  end,
}

local function handle(msg)
  if msg.method == "exit" then
    finish()
    return
  end
  if msg.id == nil or msg.method == nil then
    return -- a notification, or a response to a request of ours (none are sent)
  end
  local h = handlers[msg.method]
  if h then
    send({ jsonrpc = "2.0", id = msg.id, result = h(msg.params) })
  else
    send({
      jsonrpc = "2.0",
      id = msg.id,
      error = { code = -32601, message = "method not found: " .. msg.method },
    })
  end
end

local buf = ""

stdin:read_start(function(err, chunk)
  if err or not chunk then
    finish()
    return
  end
  buf = buf .. chunk
  while true do
    local header_end = buf:find("\r\n\r\n", 1, true)
    if not header_end then
      return
    end
    local len = tonumber(buf:sub(1, header_end - 1):match("[Cc]ontent%-[Ll]ength:%s*(%d+)"))
    if not len or #buf < header_end + 3 + len then
      return
    end
    local body = buf:sub(header_end + 4, header_end + 3 + len)
    buf = buf:sub(header_end + 4 + len)
    local ok, msg = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
    if ok and type(msg) == "table" then
      handle(msg)
    end
  end
end)

while not done do
  vim.wait(1000, function()
    return done
  end)
end
