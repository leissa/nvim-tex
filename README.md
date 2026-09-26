# nvim-tex

[![CI](https://img.shields.io/github/actions/workflow/status/leissa/nvim-tex/ci.yml?branch=master&label=CI&logo=github&style=flat-square)](https://github.com/leissa/nvim-tex/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white&style=flat-square)](https://neovim.io)
[![Lua](https://img.shields.io/badge/made%20with-Lua-2C2D72?logo=lua&logoColor=white&style=flat-square)](https://www.lua.org)

A LaTeX plugin for Neovim, in the spirit of
[VimTeX](https://github.com/lervag/vimtex), but Neovim-only and written from
scratch in Lua.

Two rules shape the design:

- **Neovim only.** No Vimscript, no Vim compatibility layer.
- **Structure from tree-sitter, language intelligence from the LSP.** The
  plugin ships no LaTeX parser and no syntax-group heuristics of its own.
  Motions, text objects and the `ds`/`cs`/`ts` edits read the `latex` parse
  tree; completion, diagnostics, references and rename come from `texlab`.

What is left is the part neither of those covers: driving `latexmk`, the PDF
viewer, SyncTeX in both directions, and the quickfix list.

## Status

Milestone 1 is done: LSP and tree-sitter integration, `latexmk` control with
the usual options, viewer and SyncTeX, quickfix, table of contents, and the
VimTeX mapping set including the insert-mode math mappings. See
[Not implemented yet](#not-implemented-yet).

## Requirements

- Neovim 0.10+ (0.11+ recommended)
- The `latex` tree-sitter parser — `:TSInstall latex`
- `latexmk`

Optional: `texlab`, a SyncTeX-capable viewer (zathura, sioyek, okular, Skim),
`dbus-send` for zathura forward search, `texdoc` for `K`.

`:checkhealth nvim-tex` reports what is missing.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'nvim-tex',
  ft = { 'tex', 'plaintex', 'latex' },
  opts = {},
}
```

`setup` is optional — the defaults apply as soon as the plugin loads.

## Configuration

```lua
require('nvim-tex').setup({
  compiler = {
    latexmk = {
      continuous = true,   -- latexmk -pvc
      out_dir = 'build',
    },
  },
  view = { method = 'zathura' },
})
```

`:TexInfo!` prints the full effective configuration. The defaults live in
[`lua/nvim-tex/config.lua`](lua/nvim-tex/config.lua) and are documented in
`:help nvim-tex-configuration`.

## Mappings

The mapping set is VimTeX's, with **one layer removed**: `<localleader>` is
already buffer-local, so the extra `l` is redundant. VimTeX's
`<localleader>ll` is `<localleader>l` here, `<localleader>lc` is
`<localleader>c`, and so on.

| Key              | Action                                    |
| ---------------- | ----------------------------------------- |
| `<localleader>l` | start / stop compilation                  |
| `<localleader>S` | compile once                              |
| `<localleader>k` | stop — `K` stops all                      |
| `<localleader>v` | view the PDF (forward search)             |
| `<localleader>r` | reverse search                            |
| `<localleader>e` | quickfix list — `o` raw output, `q` log   |
| `<localleader>c` | clean — `C` also removes the PDF          |
| `<localleader>t` | table of contents — `T` toggles           |
| `<localleader>m` | list the insert-mode math mappings         |
| `<localleader>i` | project info — `I` full                   |
| `<localleader>g` | status — `G` for all projects             |
| `<localleader>a` | context menu (citation, ref, include)     |
| `<localleader>s` | toggle the main file                      |
| `<localleader>L` | compile the selection as a standalone doc |
| `<localleader>x` | reload — `X` clears project state         |

Motions (normal, visual, operator-pending, with a count):

| Key       | Motion                                       | Key       | Motion         |
| --------- | -------------------------------------------- | --------- | -------------- |
| `]]` `[[` | section start                                | `][` `[]` | section end    |
| `]m` `[m` | `\begin`                                     | `]M` `[M` | `\end`         |
| `]n` `[n` | math zone start                              | `]N` `[N` | math zone end  |
| `]r` `[r` | `\begin{frame}`                              | `]R` `[R` | `\end{frame}`  |
| `]/` `[/` | comment                                      | `]*` `[*` | end of comment |
| `%`       | matching `\begin` / `\end` or math delimiter |           |                |

Text objects: `ae`/`ie` environment, `ac`/`ic` command, `a$`/`i$` math,
`ad`/`id` delimiters (including `\left( … \right)`), `am`/`im` item,
`aP`/`iP` section.

Editing: `dse` `dsc` `ds$` `dsd`, `cse` `csc` `cs$` `csd`,
`tsf` `tsc` `tsb` `tss` `tse` `ts$` `tsd` `tsD`, `<F6>` surround with an
environment, `<F7>` make a command, `<F8>` add delimiter modifiers, and `]]`
in insert mode to close the current environment or delimiter.

Insert-mode math mappings (VimTeX's `imaps`): a leader — a backtick by
default — followed by a short sequence inserts a LaTeX command, but only
inside a math zone. In running text the keys are inserted unchanged, so the
backtick keeps working for quotes.

| Typed    | Inserted      | Typed     | Inserted      |
| -------- | ------------- | --------- | ------------- |
| `` `a `` | `\alpha`      | `` `D ``  | `\Delta`      |
| `` `8 `` | `\infty`      | `` `ve `` | `\varepsilon` |
| `` `. `` | `\cdot`       | `` `jl `` | `\rightarrow` |
| `#bx`    | `\mathbf{x}`  | `` `` ``  | ``` `` ```    |

`:TexImaps` (or `<localleader>m`) lists them all. The list is configuration,
so entries can be changed, removed or added:

```lua
require('nvim-tex').setup({
  imaps = {
    leader = '`',
    disabled = { 'H' },                 -- keep `H for yourself
    list = { ... },                     -- replaces the default list
  },
})

-- Or one at a time, keeping the defaults:
require('nvim-tex.imaps').add({ lhs = 'oo', rhs = '\\circ' })
```

Every mapping has a command behind it (`:TexCompile`, `:TexView`, `:TexToc`,
…), so a different layout is just a matter of mapping those instead. Groups
can be disabled individually via `mappings.motions`, `mappings.text_objects`,
`mappings.surround` and `mappings.doc_package`.

## The main file

Compilation always runs on the project's main file, never on the buffer you
happen to be in. It is found from `b:tex_main`, the `main_file` option, a
`% !TEX root = …` directive, a `\documentclass` in the buffer, or by searching
this and the parent directories. `<localleader>s` toggles between the detected
main file and the current buffer.

## SyncTeX

Forward search is triggered by `<localleader>v` and `:TexForwardSearch`.
Inverse search is pushed by the viewer: nvim-tex starts a server on demand and
hands the viewer a callback command, so ctrl-click in zathura lands on the
right line. okular needs its editor command set once in the GUI — see
`:help nvim-tex-viewer-okular`.

## Not implemented yet

- LaTeX-aware indentation, and folding beyond `treesitter.fold = true`
- Compiler backends other than `latexmk`
- Word counting and syntax-highlighting extensions

## Documentation

`:help nvim-tex`

## Testing

```sh
make test                              # the whole suite
TEST_FILE=tests/qf_spec.lua make test  # one spec file
make parser                            # build the `latex` parser into .deps
```

The suite runs in a headless Neovim against `tests/minimal_init.lua` and
brings its own runner (`tests/runner.lua`), so there is nothing to install.
The specs that exercise the parse tree — motions, text objects, the `ds`/`cs`/`ts`
edits, the table of contents — need the `latex` tree-sitter parser. They use the
one a `:TSInstall latex` left in `stdpath('data')/site/parser`, or the one
`make parser` builds into `.deps`, and skip when there is neither.
`NVIM_TEX_LATEX_PARSER` points at a specific `latex.so`.

CI runs the suite on Neovim 0.10, stable and nightly, with the parser built
from a pinned revision of
[tree-sitter-latex](https://github.com/latex-lsp/tree-sitter-latex).

## Disclaimer

This plugin was mostly created with the help of AI.

## Credits

The interface — the mapping set, the text objects, the way the compiler and
viewer are driven — is taken from
[VimTeX](https://github.com/lervag/vimtex) by Karl Yngve Lervåg, which has
been the reference LaTeX plugin for Vim and Neovim for years. nvim-tex shares
no code with it, but owes it the design.
