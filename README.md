# nvim-tex

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
VimTeX mapping set. See [Not implemented yet](#not-implemented-yet).

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

- Insert-mode math mappings (VimTeX's `imaps`)
- LaTeX-aware indentation, and folding beyond `treesitter.fold = true`
- Compiler backends other than `latexmk`
- Word counting and syntax-highlighting extensions

## Documentation

`:help nvim-tex`

## Disclaimer

This plugin was mostly created with the help of AI.

## Credits

The interface — the mapping set, the text objects, the way the compiler and
viewer are driven — is taken from
[VimTeX](https://github.com/lervag/vimtex) by Karl Yngve Lervåg, which has
been the reference LaTeX plugin for Vim and Neovim for years. nvim-tex shares
no code with it, but owes it the design.
