---@module 'lsp.core.idle_stop'
---@brief Stop a language server nobody is looking at, and bring it back when
---@brief one of its buffers is shown again.
---@description
--- A language server is started per project root and then lives as long as
--- the editor does. For most servers that is cheap; for LuaLS it is close to a
--- gigabyte per repository (measured 2026-11-18: 0.9-1 GB working set, 32 s of
--- CPU to index lib.nvim), and marksman grows with the number of Markdown files
--- under its root. Open three repositories in one session, look at one, and
--- the other two keep their gigabytes for the rest of the day.
---
--- **Idle** means two things at once, checked per client:
---
--- * none of its attached buffers is shown in any window, on any tab page --
---   a buffer that is merely loaded (hidden, in the buffer list) does not
---   count, because that is exactly the state an abandoned repository is in;
--- * it has no request in flight, so a stop never cuts off an answer someone
---   is waiting for.
---
--- A client that stays idle for the configured number of minutes is stopped.
--- One that becomes busy again in between (a buffer shown, a request sent)
--- starts its clock from zero the next time it goes idle.
---
--- **Coming back** is per buffer: the buffers a stopped client was attached to
--- are remembered, and when one of them is shown again (`BufWinEnter`) the
--- server is started for it through `lsp.core.supervisor.start` -- the normal
--- root resolution, and a reuse of the client if another buffer of the same
--- root already brought it back. A buffer opened fresh does not need this:
--- its `FileType` starts the server through `vim.lsp.enable` as always.
---
--- **Not a crash.** Every stop goes through `supervisor.expect_stop` first, so
--- auto-restart does not answer it by relaunching the server at once.
---
--- **The clock is coarse on purpose.** One timer checks every client once per
--- `CHECK_MS` (one minute, or a quarter of the shortest idle time when that is
--- shorter), so a server stops up to one interval after its idle time is up.
--- The alternative -- a timer per client, re-armed on every window and buffer
--- event -- costs work on the hot path to make a ten-minute deadline exact to
--- the second, which nobody can tell apart.
---
--- Configured by `idle_stop_minutes` (`server name -> minutes | false`); a
--- server that is not named there is never stopped.
---
---@see lsp.config.DEFAULTS
---@see lsp.core.supervisor

local autocmd = require("lib.nvim.bindings.autocmd")
local notify = require("lib.nvim.notify").create("[lsp.core.idle_stop]")

local api = vim.api
local lsp = vim.lsp
local uv = vim.uv or vim.loop

local M = {}

--- Augroup of the restart hook. Its own, like `lsp.core.supervisor`'s:
--- `lsp_nvim` belongs to the keymap layer and is cleared with it.
---@type string
M.GROUP = "lsp_nvim_idle_stop"

--- Upper bound of the check interval, in milliseconds.
---@type integer
local CHECK_MS = 60 * 1000

--- Idle time per server name, in milliseconds.
---@type table<string, integer>
local limits = {}

--- Since when (in `M._now()` milliseconds) each client has been idle without
--- interruption. Absent = busy at the last check, or never checked.
---@type table<integer, integer>
local idle_since = {}

--- Buffers whose server was stopped here, and which servers: shown again,
--- each of these is started for it.
---@type table<integer, table<string, true>>
local orphans = {}

---@type uv.uv_timer_t|nil
local timer = nil

--- The clock. A function field so the spec suite can replace it.
---@return integer
function M._now()
  return uv.now()
end

---@internal
--- Is this buffer shown in any window, on any tab page?
---@param bufnr integer
---@return boolean
local function visible(bufnr)
  return api.nvim_buf_is_valid(bufnr) and #vim.fn.win_findbuf(bufnr) > 0
end

---@internal
--- Does the client have a request in flight? `client.requests` holds the ones
--- sent and not yet answered (`type = "pending"`), and those being cancelled.
---@param client vim.lsp.Client
---@return boolean
local function has_pending_request(client)
  for _, request in pairs(client.requests or {}) do
    if type(request) == "table" and request.type == "pending" then
      return true
    end
  end
  return false
end

---@internal
--- Is anyone using this client right now?
---@param client vim.lsp.Client
---@return boolean
local function busy(client)
  if has_pending_request(client) then
    return true
  end
  for bufnr in pairs(client.attached_buffers or {}) do
    if visible(bufnr) then
      return true
    end
  end
  return false
end

---@internal
--- Stop one idle client and remember its buffers for the way back.
---@param client vim.lsp.Client
---@return nil
local function stop(client)
  for bufnr in pairs(client.attached_buffers or {}) do
    if api.nvim_buf_is_valid(bufnr) then
      orphans[bufnr] = orphans[bufnr] or {}
      orphans[bufnr][client.name] = true
    end
  end
  idle_since[client.id] = nil
  -- Before the stop, or auto-restart reads the exit as a crash.
  require("lsp.core.supervisor").expect_stop(client.id)
  local ok, err = pcall(client.stop, client)
  if not ok then
    notify.warn(("could not stop %s: %s"):format(client.name, tostring(err)))
    return
  end
  -- Into the LSP log, not a notification: the stop is routine, the restart
  -- is automatic, and a message every time a hidden repository is tidied up
  -- would be noise. `:LspLog` is where "why did my server go away" is asked.
  pcall(
    lsp.log.info,
    ("lsp.nvim idle_stop: stopped %s (id %d), no visible buffer for %s min"):format(
      client.name,
      client.id,
      tostring(limits[client.name] / 60000)
    )
  )
end

--- One check of every client. Driven by the timer; exposed for the spec suite,
--- which calls it with a fake `M._now()`.
---@return integer[] stopped # ids of the clients stopped by this check
function M.tick()
  local now = M._now()
  ---@type integer[]
  local stopped = {}
  ---@type table<integer, true>
  local alive = {}
  for _, client in ipairs(lsp.get_clients()) do
    alive[client.id] = true
    local limit = limits[client.name]
    if limit == nil or client:is_stopped() or busy(client) then
      idle_since[client.id] = nil
    else
      local since = idle_since[client.id]
      if since == nil then
        idle_since[client.id] = now
      elseif now - since >= limit then
        stop(client)
        stopped[#stopped + 1] = client.id
      end
    end
  end
  -- Clients that went away on their own leave no clock behind.
  for id in pairs(idle_since) do
    if not alive[id] then
      idle_since[id] = nil
    end
  end
  return stopped
end

---@internal
--- A buffer was shown: start every server stopped from under it.
---@param bufnr integer
---@return nil
local function revive(bufnr)
  local names = orphans[bufnr]
  if names == nil then
    return
  end
  orphans[bufnr] = nil
  local supervisor = require("lsp.core.supervisor")
  for name in pairs(names) do
    local running = false
    for _, client in ipairs(lsp.get_clients({ bufnr = bufnr, name = name })) do
      running = running or not client:is_stopped()
    end
    if not running then
      local ok, err = pcall(supervisor.start, name, bufnr)
      if not ok then
        notify.warn(("could not restart %s: %s"):format(name, tostring(err)))
      end
    end
  end
end

--- Read `idle_stop_minutes` into milliseconds. Anything that is not a positive
--- number means "never" for that server.
---@param minutes table<string, number|false>|false|nil
---@return table<string, integer>
local function to_limits(minutes)
  ---@type table<string, integer>
  local out = {}
  if type(minutes) ~= "table" then
    return out
  end
  for name, value in pairs(minutes) do
    if type(name) == "string" and type(value) == "number" and value > 0 then
      out[name] = math.max(1, math.floor(value * 60 * 1000))
    end
  end
  return out
end

--- Start (or restart) idle supervision.
---
--- Idempotent: a second call replaces the limits, the timer and the augroup.
--- With no server configured nothing is registered at all -- no timer, no
--- autocommand.
---@param minutes table<string, number|false>|false|nil # `idle_stop_minutes`
---@param opts { timer?: boolean }|nil # `timer = false`: no timer; the spec suite drives `M.tick()` itself.
---@return nil
function M.setup(minutes, opts)
  opts = opts or {}
  M.detach()
  limits = to_limits(minutes)

  local shortest = nil
  for _, limit in pairs(limits) do
    shortest = shortest and math.min(shortest, limit) or limit
  end
  if shortest == nil then
    return
  end

  local group = autocmd.group(M.GROUP, true)
  autocmd.create("BufWinEnter", function(args)
    revive(args.buf)
  end, {
    group = group,
    desc = "lsp.nvim: restart a server stopped while this buffer was hidden",
  })
  autocmd.create("BufWipeout", function(args)
    orphans[args.buf] = nil
  end, {
    group = group,
    desc = "lsp.nvim: forget a wiped buffer's idle-stopped servers",
  })

  if opts.timer ~= false then
    local interval = math.max(1000, math.min(CHECK_MS, math.floor(shortest / 4)))
    timer = uv.new_timer()
    if timer then
      timer:start(interval, interval, vim.schedule_wrap(M.tick))
    end
  end
end

--- The configured idle time of a server, in milliseconds, or nil for never.
---@param name string
---@return integer|nil
function M.limit(name)
  return limits[name]
end

--- Stop the timer, drop the hooks and the bookkeeping. Clients already stopped
--- stay stopped; their buffers start them again through `FileType` only.
---@return nil
function M.detach()
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
    timer = nil
  end
  pcall(api.nvim_del_augroup_by_name, M.GROUP)
  limits = {}
  idle_since = {}
  orphans = {}
end

return M
