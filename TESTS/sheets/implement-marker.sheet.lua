-- Live check A6 of the lspsaga replacements (task lsp.nvim/live-check-lspsaga-replacements): the
-- implementation marker (` 1 impl` at the end of the line of an interface that something implements)
-- appears, updates after a change, and is never on the wrong line while typing in Insert mode. A stub
-- server answers documentSymbol (read from the buffer, so the symbols follow the text) and
-- `textDocument/implementation` (one implementation for `Repo`, none for `Lonely`).
return {
  id = "lsp.implement-marker",
  title = "lsp.nvim: the implementation marker follows its interface, also while typing in Insert mode",
  task = "lsp.nvim/live-check-lspsaga-replacements",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.laststatus = 0
      local root = vim.fn.tempname()
      vim.fn.mkdir(root, "p")
      local file = root .. "/repo.stubft"
      vim.fn.writefile({
        "interface Repo { find(): void }",
        "interface Lonely { x: number }",
        "class SqlRepo implements Repo {}",
      }, file)
      require("lsp").setup({ implement = { enable = true, filetypes = { stubft = true }, debounce_ms = 100 } })
      vim.cmd.edit(vim.fn.fnameescape(file))
      vim.bo.filetype = "stubft"
      local S = dofile(vim.fn.getcwd() .. "/TESTS/support/stub_server.lua")
      local uri = vim.uri_from_fname(file)
      local function lines() return vim.api.nvim_buf_get_lines(vim.uri_to_bufnr(uri), 0, -1, false) end
      S.start({
        name = "stubimpl", bufnr = 0, root = root,
        capabilities = { documentSymbolProvider = true, implementationProvider = true },
        handlers = {
          ["textDocument/documentSymbol"] = function()
            local out = {}
            for i, text in ipairs(lines()) do
              local name = text:match("^interface (%w+)")
              if name then
                out[#out + 1] = { name = name, kind = 11, selectionRange = S.range(i - 1, 10, 10 + #name),
                  range = { start = { line = i - 1, character = 0 }, ["end"] = { line = i - 1, character = #text } } }
              end
            end
            return out
          end,
          ["textDocument/implementation"] = function(params)
            local text = lines()[params.position.line + 1] or ""
            if text:find("Repo", 1, true) then
              return { { uri = uri, range = S.range(2, 6, 13) } }
            end
            return {}
          end,
        },
      })
      -- the markers as { line text, marker text } pairs
      _G.markers = function()
        local ns = vim.api.nvim_get_namespaces()["lsp_nvim_implement"]
        local out = {}
        for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
          local text = m[4].virt_text and m[4].virt_text[1][1] or ""
          out[#out + 1] = { line = vim.api.nvim_buf_get_lines(0, m[2], m[2] + 1, false)[1], text = text }
        end
        return out
      end]],
      note = "a TypeScript-like buffer with two interfaces, one implemented; the marker feature on for this filetype",
    },
    {
      wait = [[#_G.markers() == 1]],
      timeout = 5000,
      note = "after a moment there is one marker",
    },
    {
      expect = [[_G.markers()[1].text == " 1 impl" and _G.markers()[1].line:find("^interface Repo") ~= nil]],
      note = "it is ` 1 impl`, and it is on `interface Repo`, not on `Lonely`",
    },
    {
      input = "ggOa line above",
      note = "open a line above the interface and type, staying in Insert mode",
    },
    {
      wait = [[vim.api.nvim_get_mode().mode == "i" and vim.api.nvim_get_current_line() == "a line above"]],
      note = "typing in Insert mode",
    },
    {
      expect = [[#_G.markers() == 1 and _G.markers()[1].line:find("^interface Repo") ~= nil]],
      note = "while typing, the marker went down with its interface and is not on the new line",
    },
    { keys = "<Esc>", note = "leave Insert mode" },
    {
      wait = [[(function() local m = _G.markers() return #m == 1 and m[1].line:find("^interface Repo") ~= nil end)()]],
      timeout = 5000,
      note = "after the debounce there is still exactly one marker, on `interface Repo`",
    },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 2, 3, false, { "interface Third { y: string }", "interface Repo2 { z: number }" })]],
      note = "change the text: two more interfaces, one of them with `Repo` in its name",
    },
    {
      wait = [[(function() local m = _G.markers() return #m == 2 end)()]],
      timeout = 5000,
      note = "the markers update after the change: Repo and Repo2",
    },
    {
      expect = [[(function()
        for _, m in ipairs(_G.markers()) do
          if not m.line:find("^interface Repo") then return false end
        end
        return true
      end)()]],
      note = "every marker sits on an interface that has implementations, none on Lonely or Third",
    },
  },
  judge = {},
  manual = {
    "with a real tsserver on a real project the marker updates without a visible flicker while typing fast (the stub answers at once)",
  },
}
