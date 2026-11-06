# Doctor

`:LspDoctor` in six reports — `startup`, `resolve`, `buffer`, `capabilities`,
`probe`, `all` — answering the per-buffer questions: which servers are
expected, which are running, whether their executables resolve, where the
filetype → server chain breaks, what the clients advertise, and where two
providers overlap.

Five of them observe. `probe` provokes: it hands the attached clients a buffer
they cannot parse and reports whether diagnostics come back — the only way to
tell a clean file from a dead pipeline, since both look like an empty gutter.
It is not part of `all`, because it is the only report that costs anything.

The same provocation runs in the test suite:
[`TESTS/lsp/probe_live_spec.lua`](../../TESTS/lsp/probe_live_spec.lua) starts a
real language server, hands `probe` a file with a syntax error and requires an
answer — the one case that exercises the chain instead of stubbing it. It skips
where no server is installed, loudly and by name, and fails rather than skips
under `CI`.

Reachable both ways: `:LspDoctor [mode]` and `:Lsp doctor [mode]` take the same
mode list, from the same table, so the two cannot come to offer different
report names. The bare `:LspDoctor` runs `all`; the bare `:Lsp doctor` runs
`startup`, because that route opens a scratch split and the question one
arrives with is almost always "why is my server not running".

- **Module:** `lspdoctor/`
- **Config:** `lspdoctor`, `lspdoctor.probe_timeout`

The `lspdoctor` options besides `probe_timeout`:

| Option | Default | What it does |
| --- | --- | --- |
| `scratch_filetype` | `"markdown"` | Filetype of the scratch buffer a report is exported to |
| `auto_open_scratch` | `true` | Open that scratch buffer by itself when a report is long (`scratch_threshold` lines, default `20`) |
| `show_capabilities` | `true` | Include the capabilities section in the reports |
| `show_workspace` | `true` | Include the workspace section |
| `show_tools` | `true` | Include the section on the extra tools |
| `show_conflicts` | `true` | Detect and show potential provider conflicts (formatting, diagnostics) |
- **Commands:** `:LspDoctor[!] [mode]`, `:Lsp doctor [mode]`
