--- Covers `lsp.core.idle_stop`: a client whose buffers are all out of sight is
--- stopped after its idle time, one with a visible buffer or a request in flight
--- is not, and a stopped client comes back when one of its buffers is shown.
---
--- The clock is fake: `idle_stop._now` is replaced and `tick()` is called by the
--- case, with `setup(..., { timer = false })` so no real timer runs. The server
--- is the in-process stub (`TESTS/support/stub_server.lua`), so stopping and
--- restarting are the real `vim.lsp` paths without a process.

local tracker = dofile(vim.fn.getcwd() .. "/TESTS/support/scratch.lua")
local S = dofile(vim.fn.getcwd() .. "/TESTS/support/stub_server.lua")

local NAME = "idle_stub"
local MIN = 60 * 1000

describe("lsp.core.idle_stop", function()
  local idle, done_tracking, clock, real_now
  local root = vim.fs.normalize(vim.fn.getcwd())

  before_each(function()
    done_tracking = tracker.track()
    package.loaded["lsp.core.idle_stop"] = nil
    idle = require("lsp.core.idle_stop")
    clock = 0
    real_now = idle._now
    idle._now = function()
      return clock
    end
    vim.lsp.config(NAME, { cmd = S.cmd({ name = NAME }), root_dir = root })
  end)

  after_each(function()
    idle._now = real_now
    idle.detach()
    for _, client in ipairs(vim.lsp.get_clients({ name = NAME })) do
      client:stop(true)
    end
    vim.wait(2000, function()
      return #vim.lsp.get_clients({ name = NAME }) == 0
    end, 10)
    done_tracking()
  end)

  --- A file-like buffer with the stub attached, shown in the current window.
  ---@return integer bufnr
  ---@return vim.lsp.Client client
  local function attached_buffer()
    local bufnr = vim.api.nvim_get_current_buf()
    -- Named, never written: a nameless empty buffer is one `:edit` would take
    -- over, and a stub server attached to it would see its name change.
    vim.api.nvim_buf_set_name(bufnr, root .. "/__idle_stop_spec_buffer__.txt")
    vim.bo[bufnr].bufhidden = "hide"
    local id = S.start({ name = NAME, bufnr = bufnr, root = root })
    assert.is_number(id)
    local client = assert(vim.lsp.get_client_by_id(id))
    vim.wait(2000, function()
      return client.initialized == true
    end, 10)
    return bufnr, client
  end

  --- Show another buffer in the window, so `bufnr` stays loaded but hidden.
  ---@return integer other
  local function hide()
    local other = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_win_set_buf(0, other)
    return other
  end

  ---@param client vim.lsp.Client
  ---@return boolean
  local function wait_stopped(client)
    return vim.wait(2000, function()
      return client:is_stopped()
    end, 10)
  end

  it("stops a client whose buffers are all hidden, once its idle time is up", function()
    idle.setup({ [NAME] = 10 }, { timer = false })
    local _, client = attached_buffer()
    hide()

    assert.are.same({}, idle.tick()) -- the clock starts here
    clock = 10 * MIN - 1
    assert.are.same({}, idle.tick())
    clock = 10 * MIN
    assert.are.same({ client.id }, idle.tick())
    assert.is_true(wait_stopped(client))
  end)

  it("never stops a client with a buffer in a window", function()
    idle.setup({ [NAME] = 10 }, { timer = false })
    local _, client = attached_buffer()

    idle.tick()
    clock = 600 * MIN
    assert.are.same({}, idle.tick())
    assert.is_false(client:is_stopped())
  end)

  it("never stops a client with a request in flight", function()
    idle.setup({ [NAME] = 10 }, { timer = false })
    local bufnr, client = attached_buffer()
    hide()
    -- What `Client:request` records for an unanswered request.
    client.requests[424242] = { type = "pending", bufnr = bufnr, method = "textDocument/hover" }

    idle.tick()
    clock = 60 * MIN
    local stopped = idle.tick()
    client.requests[424242] = nil
    assert.are.same({}, stopped)
    assert.is_false(client:is_stopped())
  end)

  it("restarts the clock when a buffer was visible in between", function()
    idle.setup({ [NAME] = 10 }, { timer = false })
    local bufnr, client = attached_buffer()
    local other = hide()

    idle.tick() -- idle since 0
    clock = 5 * MIN
    vim.api.nvim_win_set_buf(0, bufnr)
    idle.tick() -- busy: the clock is dropped
    vim.api.nvim_win_set_buf(0, other)
    clock = 6 * MIN
    idle.tick() -- idle since 6 min
    clock = 15 * MIN
    assert.are.same({}, idle.tick())
    clock = 16 * MIN
    assert.are.same({ client.id }, idle.tick())
    assert.is_true(wait_stopped(client))
  end)

  it("leaves a server alone that is not configured", function()
    idle.setup({ some_other_server = 1 }, { timer = false })
    local _, client = attached_buffer()
    hide()

    idle.tick()
    clock = 600 * MIN
    assert.are.same({}, idle.tick())
    assert.is_false(client:is_stopped())
  end)

  it("starts the server again when a buffer it was stopped from is shown", function()
    idle.setup({ [NAME] = 1 }, { timer = false })
    local bufnr, client = attached_buffer()
    hide()

    idle.tick()
    clock = MIN
    assert.are.same({ client.id }, idle.tick())
    assert.is_true(wait_stopped(client))

    vim.api.nvim_win_set_buf(0, bufnr) -- BufWinEnter
    local back = vim.wait(2000, function()
      local clients = vim.lsp.get_clients({ bufnr = bufnr, name = NAME })
      return #clients == 1 and clients[1].id ~= client.id
    end, 10)
    assert.is_true(back, "the server did not come back for the shown buffer")
  end)

  it("marks its stop as expected, so auto-restart does not relaunch it", function()
    local supervisor = require("lsp.core.supervisor")
    local real = supervisor.expect_stop
    local marked = {}
    supervisor.expect_stop = function(id)
      marked[#marked + 1] = id
    end
    idle.setup({ [NAME] = 1 }, { timer = false })
    local _, client = attached_buffer()
    hide()

    idle.tick()
    clock = MIN
    idle.tick()
    supervisor.expect_stop = real
    assert.are.same({ client.id }, marked)
    assert.is_true(wait_stopped(client))
  end)

  it("registers nothing when no server is configured", function()
    idle.setup({ lua_ls = false }, { timer = false })
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = idle.GROUP }))
    idle.setup(false)
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = idle.GROUP }))
    assert.is_nil(idle.limit("lua_ls"))
  end)

  it("converts minutes to milliseconds per server", function()
    idle.setup({ lua_ls = 10, marksman = 0.5, gopls = false }, { timer = false })
    assert.are.equal(10 * MIN, idle.limit("lua_ls"))
    assert.are.equal(30 * 1000, idle.limit("marksman"))
    assert.is_nil(idle.limit("gopls"))
  end)
end)
