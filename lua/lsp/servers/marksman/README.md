# lsp.servers.marksman

Marksman (Markdown) via native LSP config/enable, with a scoped diagnostics
filter. The `root_dir` registered with `vim.lsp.config` has the native
pipeline's shape and only that one: `(bufnr: integer, on_dir: fun(root:
string))`. It reads `vim.bo[bufnr].buftype` before delegating, so a
legacy lspconfig-style `root_dir(fname)` call raises -- measured,
`init.lua:53: Unknown option '<path>/README.md'`.

The polymorphism lives one level down, in `rootresolver.lua` and the
`lib.nvim.fs.polymorphic_rootresolver` it wraps: *that* resolver takes either
a buffer number or a filename, with an optional callback, and is what keeps a
"file: expected string, got number" out of the native pipeline. Reach for it,
not for `vim.lsp.config["marksman"].root_dir`, if a root is what you want.

`root_dir` also refuses to start a client for buffers with no real backing
file (`buftype ~= ""`). Marksman only accepts `file://` URIs built from an
actual path; a scratch/preview buffer with `filetype = "markdown"` but a
synthetic name -- e.g. mdview.nvim's read-only tab preview, named
`[mdview preview] foo.md (12)` -- turns into a URI with no parsable host and
crashes the server on `textDocument/didOpen` ("Invalid URI: The hostname
could not be parsed."). Not calling the `on_dir` callback for such buffers
stops the native pipeline from starting a client for them at all, so no
didOpen is ever sent.

## Relative links without `./`

marksman reads a target without a leading `./` (`[x](Replies/a.md)`) not as
relative to the document but as a path suffix matched across the whole
workspace. In a folder of cases that each have a `Replies/a.md`, the link in
one case's own `State.md` gets "Ambiguous link to document 'Replies/a.md'",
while `./Replies/a.md` is clean (measured against marksman). Readers, GitHub
and every renderer resolve it relative to the document.

The diagnostics filter drops that message when the target is a file relative
to the document (marksman sends the name decoded and without a fragment; a
link with `#x` gets "Ambiguous link to heading", hidden by its own rule). A
target that does not exist there keeps the message -- then it really is one of
several files elsewhere -- and so does a folder of that name (marksman says the
same for a wiki link `[[Project]]` next to a folder `Project/`), a
root-relative target (`/x.md`), a URL and an env link. `resolve_ambiguous_relative = false` in `lsp.servers.marksman.config`
turns it off.

## Env-variable links

marksman resolves a link target relative to the document, so
`[x]($REPOS_DIR/a/b.md)` is a folder named `$REPOS_DIR` to it: no definition, no
hover, and "Link to non-existent document" for a file that exists. The blanket
`suppress_missing_doc_links` below hid the false alarm together with every real
broken link.

`languages.env_links` (default on) changes that in two places. This module's
diagnostics filter asks `lsp.core.env_links.verdict` first: an env link whose
file exists is dropped, and anything the resolver cannot judge -- an undefined
variable -- falls through to the rules unchanged. One whose file does not exist
is **kept** (annotated with the path it was looked up at) even though the
blanket rule would hide it -- unless the in-process client is running, which
reports the broken env links itself (the file *and* the `#fragment`, which
marksman never reports for any link), and then marksman's duplicate is dropped.
Definition, hover, path completion and those diagnostics come from a separate in-process client
(`lsp.core.env_links_server`), because a handler in this server's config would
only reach requests that use client handlers, and `vim.lsp.buf.definition` does
not. See `docs/configuration.md` (`languages.env_links`).

## Memory: what marksman indexes

marksman indexes every Markdown file under its root, and its memory grows with
that number. Measured 2026-11-18 on the tasks-vault (marksman 1.0.0, 60 s after
opening one file, no request sent): 10.4k files 429 MB / 16 s CPU, the same
vault at 5.3k files 260 MB / 9 s. A README-sized repository stays near 90 MB,
which is the process itself.

- **No exclude option.** `.marksman.toml` has none. marksman skips what
  `.gitignore`, `.ignore` and `.hgignore` (in any folder) exclude, and `.git`
  itself. It does **not** read `.git/info/exclude` or the global git excludes:
  a directory ignored only there is indexed. The case that doubled the vault was
  an agent worktree under `.claude/worktrees/` -- a full second copy, excluded
  in `.git/info/exclude` only. Put such directories in the repository's
  `.gitignore`.
- **Git worktrees get no index at all.** In a linked worktree `.git` is a file,
  and marksman logs `Workspace folder is bogus` and runs per file: links to
  other files resolve to nothing there. That is marksman's decision, not this
  plugin's root resolution.
- **Out of sight, out of memory.** `idle_stop_minutes.marksman` (10 by default)
  stops an instance whose Markdown buffers are all hidden; showing one starts it
  again. That is also what keeps one instance per root affordable: sharing one
  process across roots would save the ~90 MB base per root but index all of
  them in one process, and an idle root is stopped anyway.
