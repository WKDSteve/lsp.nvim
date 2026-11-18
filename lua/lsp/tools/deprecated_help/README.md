# lsp.tools.deprecated_help

Modularized deprecated-API warning helper; `setup({ keymap = "<leader>lh" })`
wires up a keymap that surfaces the deprecation notice.

`display` decides how the help of the symbol is shown:

- `"hover"` (default): the symbol's help entry in a float, focus stays in the code
- `"help"`: `:help <symbol>` in a help window

```lua
require("lsp.tools.deprecated_help").setup({ keymap = "<leader>lh", display = "help" })
```

Through lsp.nvim's config: `tools.deprecated_help = { enable = true, display = "hover" }`.

## Help for the word under the cursor

`:Lsp help [word]` (or `require("lsp.tools.deprecated_help.word").show()`) shows
the help entry of the word under the cursor through the same float. It tries the
dotted name (`vim.api.nvim_buf_get_lines`) and then the plain word, first in the
help pages named for the buffer's filetype, then in the `:help` tags. Nothing
found ends in a message, not an error.

```lua
keymaps = { map = { word_help = "<leader>K" } },  -- no key by default
tools.deprecated_help = {
  help_pages = { lua = { "luvref" } },  -- doc/luvref.txt, or a path to a help file
}
```

The key is the keymap catalogue's `word_help` entry, so `keymaps = false` leaves
it unbound. (`require("lsp.tools.deprecated_help").setup({ word_keymap = ... })`, the
tool module set up on its own without lsp.nvim's setup(), still takes a key.)

A help page is searched for the word as a tag and for a tag that ends in it, so
`fs_stat` under the cursor finds `*uv.fs_stat()*` in `luvref.txt`. With
`display = "help"` the match is opened at its tag instead of shown in a float.
