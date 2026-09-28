# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
make test                  # whole suite (headless nvim, tests/minimal_init.lua)
make test SPEC=qf          # one spec file (basename of tests/<name>_spec.lua)
make test SPEC='qf toc'    # several
make fmt                   # stylua lua plugin tests
make fmt-check             # what CI enforces
make doc                   # regenerate doc/tags (CI checks helptags builds)
make parser                # build the pinned `latex` tree-sitter parser into .deps/
```

Specs that touch the parse tree (motions, textobj, surround, toc, indent, fold,
conceal, ts, …) call `H.need_parser()` and **skip silently** without a `latex`
parser. Run `make parser` (needs the `tree-sitter` CLI) or set
`NVIM_TEX_LATEX_PARSER=/path/to/latex.so`; `NVIM_TEX_REQUIRE_PARSER=1` (as in CI)
turns a missing parser into a failure. The parser revision is pinned in both
`Makefile` and `.github/workflows/ci.yml` — keep them in sync. CI runs Neovim
v0.10.4, stable and nightly, so code must work on 0.10.

## Design rules

- Neovim-only Lua; no Vimscript, no Vim compatibility.
- Structure comes from the tree-sitter `latex` parse tree, language
  intelligence (completion, diagnostics, rename) from `texlab`. Don't add
  regex/syntax-group heuristics for LaTeX structure. The plugin's own job is
  compiler, viewer, SyncTeX, quickfix — plus the tree-sitter-driven editing
  features.
- The mapping set and option layout follow VimTeX, minus the redundant `l`
  layer under `<localleader>` (VimTeX `<localleader>ll` → `<localleader>l`).
- The plugin has essentially no users: rename or remove options freely,
  without deprecation shims.
- Style: stylua with 2 spaces, 120 columns, single quotes (`stylua.toml`).
  Modules use `local M = {} … return M` with LuaCATS `---@` annotations and
  explanatory `---` doc comments.

## Architecture

- **Bootstrap**: `plugin/nvim-tex.lua` calls `require('nvim-tex').init()`, so
  defaults apply without `setup`. `init.lua` registers commands, the
  `latex` language for the configured filetypes, injections, and a `FileType`
  autocmd that calls `M.attach(bufnr)`, which wires up buffer options,
  tree-sitter features (conceal/indent/fold), LSP, keymaps and imaps. `setup`
  re-attaches already open buffers. `User NvimTexAttach` fires per buffer.
- **Config** (`config.lua`): one nested `M.defaults` table (the single source
  of truth for options), merged by `setup`; read everywhere via
  `config.get('compiler', 'latexmk', ...)`. New options also need documenting
  in `doc/nvim-tex.txt` (`:help nvim-tex-configuration`).
- **Projects** (`project.lua`): every buffer maps to a project keyed by the
  absolute path of its main file (`project.projects[main]`). All long-lived
  state — compiler job handle, viewer handle, collected output — lives on the
  project, so buffers of one document share a compilation. Main-file
  detection order: `b:tex_main`, `main_file` option, `% !TEX root`,
  `\begin{document}` in the buffer, an open document that `\input`s it,
  directory search.
- **Backends**: `compiler/init.lua` and `viewer/init.lua` dispatch on
  `compiler.method` / `view.method` to modules in `M.backends` (latexmk,
  tectonic; zathura, sioyek, okular, skim, general). A compiler backend
  provides `build_cmd` etc.; continuous mode needs `is_finished_line`
  (tectonic lacks it, so it is single-shot only). Viewer backends provide
  `available()` and forward-search logic; inverse search calls back through
  the global `NvimTexInverseSearch`, installed when `nvim-tex.viewer` loads.
  The compiler emits `User NvimTex<Event>` autocmds with plain data only.
- **Tree-sitter helpers** (`ts.lua`): node-type sets (`ENVIRONMENT`,
  `SECTION`, `MATH`, …), `node_at_cursor`, `ancestor`, `env_name`, `in_math`,
  etc. Motions, textobj, surround, toc, indent, fold, conceal and imaps build
  on these rather than parsing text themselves. `queries/latex/` holds the
  queries nvim-tex installs (Neovim ships none for LaTeX folds).
- **Quickfix** (`qf.lua`): parses the `.log` (`parse_log`) into items.
- **Citations** (`cite/`): DBLP search via `curl` (`cite/dblp.lua`), BibTeX
  appended to the main file's first bibliography.
- `keymaps.lua` maps keys to functions that also back the `:Tex*` commands in
  `commands.lua`; `health.lua` is `:checkhealth nvim-tex`; `info.lua` is
  `:TexInfo`.

## Tests

No external test framework: `tests/runner.lua` provides global `describe`,
`it`, `before_each`, `after_each` and the assertion table `T` (`T.eq(expected,
actual)`, `T.ok`, `T.matches`, `T.contains`, `T.raises`, `T.skip`, …).
`tests/helpers.lua` (`H`) provides temp dirs/files/buffers torn down by
`H.cleanup` (call it from `after_each`) and replaces `vim.notify` with a
recorder — assert on messages with `H.notified(pattern)`.
