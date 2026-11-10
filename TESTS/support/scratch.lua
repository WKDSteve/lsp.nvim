-- TESTS/support/scratch.lua -- remove the buffers and windows a spec case made, so testing.nvim's state guard finds
-- nothing left behind (`guards.state = "error"` in .testing.lua).
--
--   local scratch = dofile(vim.fn.getcwd() .. "/TESTS/support/scratch.lua")
--   local done
--   before_each(function() done = scratch.track() end)
--   after_each(function() done() end)
--
-- `track()` notes the buffers, windows and the current window's buffer, and puts a fresh empty buffer in that window
-- for the case; the function it returns closes every window and deletes every buffer that was not there, after
-- showing the noted buffer in the noted window again (deleting the buffer a window shows would leave a fresh [No Name]
-- in its place). A spec that keeps something across cases on purpose creates it before `track()`.

local M = {}

---@return fun() done
function M.track()
  local api = vim.api
  local bufs, wins = {}, {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    bufs[b] = true
  end
  for _, w in ipairs(api.nvim_list_wins()) do
    wins[w] = true
  end
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  -- The case starts on a fresh empty buffer of its own: `:edit` takes over an empty unnamed buffer instead of making a
  -- new one, and without this it would take over the editor's own (buffer 1) -- its name, filetype and ftplugin
  -- keymaps would outlive the case. This one is new, so it goes with the rest.
  api.nvim_win_set_buf(win, api.nvim_create_buf(true, false))

  return function()
    for _, w in ipairs(api.nvim_list_wins()) do
      if not wins[w] and api.nvim_win_is_valid(w) then
        pcall(api.nvim_win_close, w, true)
      end
    end
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_set_current_win, win)
      if api.nvim_buf_is_valid(buf) then
        pcall(api.nvim_win_set_buf, win, buf)
      end
    end
    for _, b in ipairs(api.nvim_list_bufs()) do
      if not bufs[b] and api.nvim_buf_is_valid(b) then
        pcall(api.nvim_buf_delete, b, { force = true })
      end
    end
  end
end

return M
