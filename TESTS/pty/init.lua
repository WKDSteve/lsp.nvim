-- TESTS/pty/init.lua -- the editor of the terminal specs (TESTS/lsp/pty_fzf_spec.lua): a real Neovim in tmux
-- (WSL on Windows) with lsp.nvim, a real fzf-lua and a stub language server, started as
--
--   nvim --clean -c "luafile <this file>"
--
-- Everything variable comes from the environment (the spec sets it): LSP_PTY_ROOT (lsp.nvim), LSP_PTY_RTP
-- (comma separated runtimepath entries: lib.nvim, ui.nvim, fzf-lua), LSP_PTY_SCENARIO. The editor's
-- project is a fresh temp directory, so nothing of the user's is read or written.

local root = assert(vim.env.LSP_PTY_ROOT, "LSP_PTY_ROOT")
vim.opt.shortmess:append("I")
vim.o.laststatus = 0
vim.o.swapfile = false
vim.opt.rtp:prepend(root)
for dir in (vim.env.LSP_PTY_RTP or ""):gmatch("[^,]+") do
  vim.opt.rtp:append(dir)
end
-- fzf-lua's plugin file defines :FzfLua
vim.cmd("runtime! plugin/fzf-lua.lua")

local S = dofile(root .. "/TESTS/support/stub_server.lua")

-- a SHORT path on purpose: fzf cuts a long row ("sample..") and the checks read the row text, and a
-- test runner points TMPDIR (so tempname()) deep into a sandbox
local dir = ("/tmp/lsp-pty-%d"):format(vim.uv.os_getpid())
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    vim.fn.delete(dir, "rf")
  end,
})
vim.fn.mkdir(dir, "p")
local file = dir .. "/sample.zzz"
vim.fn.writefile({
  'import { readFileSync } from "fs";',
  "",
  "export function total(a: number, b: number): number {",
  "  const x = a + 1;",
  "  const y = b * 2;",
  "  const sum = x + y;",
  "  return sum;",
  "}",
}, file)

require("lsp").setup({})
vim.cmd.edit(vim.fn.fnameescape(file))
vim.bo.filetype = "stubft"

local uri = vim.uri_from_fname(file)
local scenario = vim.env.LSP_PTY_SCENARIO or "actions"
local caps = { codeActionProvider = true }
local handlers = {
  ["textDocument/codeAction"] = function(params)
    return S.code_actions(uri, params)
  end,
}
if scenario == "hierarchy" then
  -- what gopls / clangd answer for a type and a function (the check A8 and A11 of the lspsaga task)
  local function item(name, kind, line)
    return {
      name = name,
      kind = kind,
      uri = uri,
      range = S.range(line, 0, 10),
      selectionRange = S.range(line, 0, 10),
    }
  end
  caps.typeHierarchyProvider = true
  caps.callHierarchyProvider = true
  handlers["textDocument/prepareTypeHierarchy"] = function()
    return { item("Shape", 11, 2) }
  end
  handlers["typeHierarchy/supertypes"] = function()
    return { item("BaseShape", 11, 3), item("Drawable", 11, 4) }
  end
  handlers["typeHierarchy/subtypes"] = function()
    return { item("Square", 11, 4), item("Circle", 11, 5) }
  end
  handlers["textDocument/prepareCallHierarchy"] = function()
    return { item("total", 12, 2) }
  end
  handlers["callHierarchy/incomingCalls"] = function()
    return {
      { from = item("caller_of_total", 12, 5), fromRanges = { S.range(5, 2, 7) } },
      { from = item("other_caller", 12, 6), fromRanges = { S.range(6, 2, 7) } },
    }
  end
  handlers["callHierarchy/outgoingCalls"] = function()
    return {
      { to = item("callee_of_total", 12, 6), fromRanges = { S.range(3, 2, 7) } },
      { to = item("other_callee", 12, 7), fromRanges = { S.range(4, 2, 7) } },
    }
  end
end
S.start({
  name = "stubserver",
  bufnr = 0,
  root = dir,
  capabilities = caps,
  handlers = handlers,
})
vim.wait(2000, function()
  return #vim.lsp.get_clients({ bufnr = 0, name = "stubserver" }) > 0
end, 20)
-- the spec types only after this line is on the screen
vim.cmd("echo 'PTY-READY'")
