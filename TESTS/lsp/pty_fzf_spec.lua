--- The fzf-lua windows of the lspsaga replacements (checks A1, A2, A8 and the picker half of A11 of the task
--- lsp.nvim/live-check-lspsaga-replacements) in a REAL terminal: Neovim runs inside tmux (WSL on Windows,
--- testing.nvim's `testing.pty`, tier 2.5) with lsp.nvim, a real fzf-lua and the fzf binary, a stub
--- language server answers (TESTS/support/stub_server.lua), and the screen of the terminal is read back.
---
--- Skipped (a reported `n/a`, never green) without tmux, without the fzf binary on the host of tmux, without
--- fzf-lua on this machine or without testing.nvim on the runtimepath. The editor is TESTS/pty/init.lua.
---@diagnostic disable: undefined-global
-- luacheck: read globals describe it

local this = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(this)))
local BS = string.char(92)
local ESC = string.char(27)

---Windows path -> the path WSL sees (`E:\x` -> `/mnt/e/x`); Linux paths stay.
---@param path string
---@return string
local function host_path(path)
  path = path:gsub(BS, "/")
  local drive, rest = path:match("^(%a):(.*)$")
  if not drive then
    return path
  end
  return "/mnt/" .. drive:lower() .. rest
end

---The checkout of a plugin dependency: the runtimepath of this editor, then the usual places.
---@param name string e.g. "fzf-lua"
---@param module string a Lua module of it
---@return string|nil
local function checkout(name, module)
  local found = vim.api.nvim_get_runtime_file(
    "lua/" .. module:gsub("%.", "/") .. "/init.lua",
    false
  )[1] or vim.api.nvim_get_runtime_file("lua/" .. module:gsub("%.", "/") .. ".lua", false)[1]
  if found then
    return (vim.fn.fnamemodify(found, ":p"):gsub(BS, "/"):match("^(.*)/lua/"))
  end
  local env = vim.uv.os_getenv((name:upper():gsub("[^%w]", "_")) .. "_DIR")
  -- no nil in the list: ipairs would stop there
  local places = {
    env or "",
    vim.fs.dirname(root) .. "/" .. name,
    root .. "/.deps/" .. name,
    (vim.uv.os_getenv("LOCALAPPDATA") or "") .. "/nvim-data/lazy/" .. name,
    (vim.uv.os_getenv("HOME") or "") .. "/.local/share/nvim/lazy/" .. name,
  }
  for _, p in ipairs(places) do
    if p and p ~= "" and vim.fn.isdirectory(p .. "/lua") == 1 then
      return (p:gsub(BS, "/"))
    end
  end
  return nil
end

---Why the terminal specs cannot run here, or nil.
---@return string|nil reason, table|nil pty, string|nil rtp
local function prerequisites()
  local ok_pty, pty = pcall(require, "testing.pty")
  if not ok_pty then
    return "testing.nvim is not on the runtimepath (testing.pty)"
  end
  local available, reason = pty.available()
  if not available then
    return reason
  end
  local fzf_lua, lib, ui =
    checkout("fzf-lua", "fzf-lua"), checkout("lib.nvim", "lib.nvim"), checkout("ui.nvim", "ui")
  if not fzf_lua then
    return "fzf-lua is not installed on this machine"
  end
  if not (lib and ui) then
    return "lib.nvim or ui.nvim was not found"
  end
  -- the fzf binary on the host of tmux
  local argv = { "sh", "-c", "command -v fzf" }
  if require("testing.platform").is_windows() then
    argv = { "wsl" }
    local distro = vim.uv.os_getenv("TESTING_WSL_DISTRO")
    if distro and distro ~= "" then
      vim.list_extend(argv, { "-d", distro })
    end
    vim.list_extend(argv, { "--exec", "sh", "-c", "command -v fzf" })
  end
  local res = vim.system(argv, { text = true }):wait(15000)
  if res.code ~= 0 then
    return "the fzf binary is not installed on the host of tmux"
  end
  return nil, pty, table.concat({ host_path(lib), host_path(ui), host_path(fzf_lua) }, ",")
end

local skip, pty, rtp = prerequisites()

---The screen without colour sequences.
---@param s table session
---@return string
local function plain(s)
  return (s:screen():gsub(ESC .. "%[[%d;:]*m", ""))
end

---Wait until the screen (without colour sequences, which split words) holds `needle`.
---@param s table session
---@param needle string
---@param timeout_ms integer
---@return boolean
local function waits(s, needle, timeout_ms)
  local deadline = vim.uv.hrtime() + timeout_ms * 1e6
  repeat
    if plain(s):find(needle, 1, true) then
      return true
    end
    vim.wait(100)
  until vim.uv.hrtime() > deadline
  return false
end

---Start the terminal editor of a scenario and wait until it is ready.
---@param scenario "actions"|"hierarchy"
---@return table session
local function editor(scenario)
  local session, err = pty.open({
    "env",
    "LSP_PTY_ROOT=" .. host_path(root),
    "LSP_PTY_SCENARIO=" .. scenario,
    "LSP_PTY_RTP=" .. rtp,
    "nvim",
    "--clean",
    "-c",
    "luafile " .. host_path(root) .. "/TESTS/pty/init.lua",
  }, { cols = 110, rows = 30 })
  assert(session, err)
  assert(
    waits(session, "PTY-READY", 25000),
    "the terminal editor did not get ready:\n" .. plain(session)
  )
  return session
end

---Type a normal-mode key sequence (tmux sends the words one after the other).
---@param s table session
---@param keys string
local function type_keys(s, keys)
  s:send({ keys }, true)
end

---Wait until a text that only the open picker shows is off the screen.
---@param s table session
---@param marker string
local function picker_gone(s, marker)
  local deadline = vim.uv.hrtime() + 10e9
  while plain(s):find(marker, 1, true) and vim.uv.hrtime() < deadline do
    vim.wait(100)
  end
  assert(not plain(s):find(marker, 1, true), "the picker did not close:\n" .. plain(s))
end

---Close the picker with Escape and wait until its prompt is off the screen.
---@param s table session
---@param marker string text only the open picker shows
local function close_picker(s, marker)
  s:send({ "Escape" })
  picker_gone(s, marker)
end

describe("lspsaga replacements in a real terminal (fzf-lua)", function()
  if skip then
    it("n/a", function()
      print("n/a  " .. skip)
    end)
    return
  end

  local session
  after_each(function()
    if session then
      session:close()
      session = nil
    end
  end)

  it(
    "A1: lsa opens the real fzf window with a diff preview, no warning, and the action applies",
    function()
      session = editor("actions")
      type_keys(session, "lsa")
      assert(waits(session, "Code actions>", 10000), plain(session))
      assert(waits(session, "Add missing import", 10000), plain(session))
      assert(
        waits(session, "+import { added } from 'x';", 10000),
        "the diff preview of the edit:\n" .. plain(session)
      )
      local screen = plain(session)
      assert(not screen:find("register_ui_select", 1, true), "no fzf-lua warning in the window")
      session:send({ "Enter" })
      picker_gone(session, "Code actions>")
      assert(
        waits(session, "import { added } from 'x';", 10000),
        "the chosen action was applied:\n" .. plain(session)
      )
      -- the warning would have been a message
      type_keys(session, ":messages")
      session:send({ "Enter" })
      vim.wait(500)
      local messages = plain(session)
      assert(
        not messages:find("register_ui_select", 1, true),
        "no register_ui_select message:\n" .. messages
      )
    end
  )

  it("A2: gra in Visual mode lists the actions of the selection (Extract function)", function()
    session = editor("actions")
    -- Normal mode: one line, no multi-line refactor
    type_keys(session, "lsa")
    assert(waits(session, "Add missing import", 10000), plain(session))
    assert(not plain(session):find("Extract function", 1, true), "Normal mode offers no extraction")
    session:send({ "Escape" })
    vim.wait(500)
    -- Visual mode on lines 4-6
    type_keys(session, "4GV2jgra")
    assert(waits(session, "Code actions>", 10000), plain(session))
    assert(
      waits(session, "Extract function", 10000),
      "the selection offers the extraction:\n" .. plain(session)
    )
    assert(plain(session):find("2/2", 1, true), "both actions are listed")
    type_keys(session, "Extract")
    vim.wait(500)
    session:send({ "Enter" })
    picker_gone(session, "Code actions>")
    assert(waits(session, "// extracted", 10000), "the extraction was applied:\n" .. plain(session))
  end)

  it(
    "A8: lsh and lsH list sub- and supertypes in the picker; a server without them gets a sentence",
    function()
      session = editor("hierarchy")
      type_keys(session, "3Glsh")
      assert(waits(session, "2/2", 10000), "supertypes picker:\n" .. plain(session))
      local super = plain(session)
      assert(super:find("sample.zzz:4:1", 1, true) and super:find("sample.zzz:5:1", 1, true), super)
      close_picker(session, "2/2")
      type_keys(session, "lsH")
      assert(waits(session, "sample.zzz:6:1", 10000), "subtypes picker:\n" .. plain(session))
      session:close()
      -- gopls-less case: a server that offers no type hierarchy (the TS side of A8)
      session = editor("actions")
      type_keys(session, "lsh")
      assert(
        waits(session, "no attached server offers a type hierarchy", 10000),
        "the sentence naming the servers that can:\n" .. plain(session)
      )
      assert(not plain(session):find("No results", 1, true), "no 'No results' after a wait")
    end
  )

  it("A11 (picker half): lsc and lsC list the callers and callees in the fzf window", function()
    session = editor("hierarchy")
    type_keys(session, "3Glsc")
    assert(waits(session, "caller_of_total", 10000), "incoming calls:\n" .. plain(session))
    assert(plain(session):find("other_caller", 1, true), "both callers are listed")
    close_picker(session, "2/2")
    type_keys(session, "lsC")
    assert(waits(session, "callee_of_total", 10000), "outgoing calls:\n" .. plain(session))
  end)
end)
