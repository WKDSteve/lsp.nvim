---@module 'lsp.core.lua_root'
---@brief Jump from inside a nested Lua table or function to the head of the structure around it.
---@description
--- The source of truth is the Treesitter tree, not `textDocument/documentSymbol`:
--- lua_ls reports no symbol for an anonymous table (`opts = { a = { b = 1 } }`
--- inside a call), and a jump that works only where the server happens to name
--- the structure would be a surprise. The tree also needs no running client.
---
--- A "structure" is a `table_constructor`, a `function_declaration` or a
--- `function_definition`. `chain()` lists those that contain the cursor,
--- innermost first. The default target is the outermost one (the root of what
--- the cursor is in); a count `N` means "N levels up" and is clamped to the
--- outermost. Pressing the key again on the root is a no-op with a short
--- message, because there is nothing above it.
---
--- The jump sets the previous-context mark, so `<C-o>` returns.
---
---@see lsp.bindings.actions

local M = {}

---@type table<string, true>
local STRUCTURES = {
  table_constructor = true,
  function_declaration = true,
  function_definition = true,
}

--- Enclosing structures of a node, innermost first (the node itself counts).
---@param node TSNode|nil
---@return TSNode[] chain
function M.chain(node)
  ---@type TSNode[]
  local out = {}
  while node do
    if STRUCTURES[node:type()] then
      out[#out + 1] = node
    end
    node = node:parent()
  end
  return out
end

--- Pick the target out of a chain.
---@param chain TSNode[] innermost first
---@param count? integer levels up (1 = innermost); nil or 0 = outermost
---@return TSNode|nil
function M.pick(chain, count)
  if #chain == 0 then
    return nil
  end
  if not count or count < 1 then
    return chain[#chain]
  end
  return chain[math.min(count, #chain)]
end

--- Jump to the opening line of the enclosing structure.
---@param opts? { count?: integer, center?: boolean, bufnr?: integer }
---@return boolean jumped
---@return string|nil reason why nothing happened
function M.jump(opts)
  opts = opts or {}
  local buf = opts.bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "lua" then
    return false, "not a Lua buffer"
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "lua")
  if not ok or not parser then
    return false, "no Lua Treesitter parser"
  end
  parser:parse()
  local cur = vim.api.nvim_win_get_cursor(0)
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { cur[1] - 1, cur[2] } })
  local target = M.pick(M.chain(node), opts.count)
  if not target then
    return false, "not inside a table or function"
  end
  local row = target:range()
  if row + 1 == cur[1] then
    return false, "already on the head of the structure"
  end
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  vim.cmd("normal! ^")
  if opts.center then
    vim.cmd("normal! zz")
  end
  return true, nil
end

return M
