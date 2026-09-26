--- Default configuration and user override handling.
---
--- The layout deliberately mirrors vimtex's `g:vimtex_*` options, but grouped
--- into nested tables instead of a flat namespace.
local M = {}

---@type table
M.defaults = {
  enabled = true,

  --- Filetypes the plugin attaches to.
  filetypes = { 'tex', 'plaintex', 'latex' },

  --- Explicit main file. A string, or a function(bufnr) -> string|nil.
  --- When nil the main file is detected (see `nvim-tex.project`).
  main_file = nil,

  cache_root = vim.fs.joinpath(vim.fn.stdpath('cache'), 'nvim-tex'),

  compiler = {
    enabled = true,
    --- Only 'latexmk' is implemented; the dispatch table lives in
    --- `nvim-tex.compiler` so further backends can be added.
    method = 'latexmk',
    --- Suppress "started"/"stopped"/"success" messages.
    silent = false,
    --- Compile automatically when the buffer is written (single shot only;
    --- continuous mode does its own watching).
    build_on_save = false,

    latexmk = {
      executable = 'latexmk',
      --- `true` runs `latexmk -pvc`, watching for changes until stopped.
      continuous = true,
      options = {
        '-verbose',
        '-file-line-error',
        '-synctex=1',
        '-interaction=nonstopmode',
      },
      --- Relative paths are taken relative to the main file's directory.
      aux_dir = '',
      out_dir = '',
      --- Extra extensions for `:TexClean`, space separated, no leading dot.
      clean_ext = '',
      --- Functions called with every line of compiler output.
      hooks = {},
      --- TeX program directive (`% !TeX program = ...`) -> latexmk engine flag.
      engines = {
        ['_'] = '-pdf',
        ['pdflatex'] = '-pdf',
        ['lualatex'] = '-lualatex',
        ['xelatex'] = '-xelatex',
        ['latex'] = '-pdfdvi',
        ['pdftex'] = '-pdf',
        ['luatex'] = '-lualatex',
        ['xetex'] = '-xelatex',
        ['context (pdftex)'] = '-pdf -pdflatex=texexec',
        ['context (luatex)'] = '-pdf -pdflatex=context',
        ['context (xetex)'] = '-pdf -pdflatex=texexec --xtx',
      },
    },
  },

  view = {
    enabled = true,
    --- 'auto' picks the first available of zathura, sioyek, okular, skim,
    --- general. Set explicitly to override.
    method = 'auto',
    --- Jump to the cursor position in the PDF right after opening the viewer.
    forward_search_on_start = true,

    zathura = {
      executable = 'zathura',
      args = {},
      --- Use the D-Bus interface for forward search on a running instance.
      use_dbus = true,
    },
    sioyek = {
      executable = 'sioyek',
      args = {},
    },
    okular = {
      executable = 'okular',
      args = { '--unique' },
    },
    skim = {
      executable = '/Applications/Skim.app/Contents/SharedSupport/displayline',
      args = {},
    },
    --- Fallback. `@pdf`, `@line`, `@col`, `@tex` are substituted.
    general = {
      executable = 'xdg-open',
      args = { '@pdf' },
    },
  },

  qf = {
    enabled = true,
    --- Open the quickfix window when the compilation produced entries.
    auto_open = true,
    --- Also open it when there are only warnings (no errors).
    open_on_warning = true,
    --- Jump to the first entry when opening.
    autojump = false,
    --- Keep the quickfix window open after a successful run.
    auto_close = true,
    --- Lua patterns; matching messages are dropped.
    ignore_filters = {},
    --- Height of the quickfix window.
    height = 8,
  },

  lsp = {
    enabled = true,
    --- Set to false if you configure texlab yourself (lspconfig, etc.).
    --- The plugin also backs off when a texlab client is already attached.
    name = 'texlab',
    cmd = { 'texlab' },
    --- Merged into the `texlab` settings table.
    settings = {
      texlab = {
        --- nvim-tex drives latexmk itself, so texlab's builder stays idle.
        build = {
          onSave = false,
          forwardSearchAfter = false,
        },
        forwardSearch = {},
        chktex = {
          onOpenAndSave = false,
          onEdit = false,
        },
        diagnosticsDelay = 300,
        formatterLineLength = 80,
        latexFormatter = 'latexindent',
        bibtexFormatter = 'texlab',
      },
    },
    --- Extra keys merged into the `vim.lsp.start` config (capabilities,
    --- on_attach, handlers, ...).
    config = {},
  },

  treesitter = {
    enabled = true,
    --- Warn once when the `latex` parser is missing.
    warn_missing_parser = true,
    --- Enable `:h treesitter-highlight` for LaTeX buffers.
    highlight = true,
    --- Use tree-sitter based folding.
    fold = false,
  },

  toc = {
    --- Window layout: 'vsplit', 'split' or 'tab'.
    split = 'vsplit',
    width = 40,
    height = 15,
    --- Close the TOC after jumping to an entry.
    close_after_jump = true,
    --- Entry types to include.
    show_labels = false,
    show_includes = true,
    show_todos = true,
  },

  --- Options for the ds*/cs*/ts* editing mappings.
  edit = {
    --- `tse` cycles the surrounding environment through this map.
    env_toggle_map = {
      itemize = 'enumerate',
      enumerate = 'description',
      description = 'itemize',
      equation = 'align',
      align = 'gather',
      gather = 'equation',
      figure = 'table',
      table = 'figure',
    },
    --- `ts$` toggles between inline and displayed math.
    env_toggle_math_map = {
      ['$'] = '\\[',
      ['\\('] = '\\[',
      ['\\['] = '$',
    },
    --- Commands recognised by `tsf` (fraction toggling).
    toggle_fractions = { 'frac', 'dfrac', 'tfrac', 'cfrac' },
    --- Commands `tsc` may star. `nil` means "any command".
    toggle_star_cmds = nil,
    --- Modifier pairs cycled through by `tsd` / `tsD`; the empty modifier is
    --- always the first element of the cycle.
    delim_toggle_mod_list = {
      { '\\left', '\\right' },
    },
    --- Delimiter pairs offered by `csd`, keyed by the character you type.
    delim_list = {
      ['('] = { '(', ')' },
      [')'] = { '(', ')' },
      ['['] = { '[', ']' },
      [']'] = { '[', ']' },
      ['{'] = { '\\{', '\\}' },
      ['}'] = { '\\{', '\\}' },
      ['<'] = { '\\langle', '\\rangle' },
      ['>'] = { '\\langle', '\\rangle' },
      ['|'] = { '|', '|' },
      ['v'] = { '\\lvert', '\\rvert' },
      ['V'] = { '\\lVert', '\\rVert' },
      ['c'] = { '\\lceil', '\\rceil' },
      ['f'] = { '\\lfloor', '\\rfloor' },
    },
  },

  mappings = {
    enabled = true,
    --- `<localleader>` is already buffer-local, so unlike vimtex there is no
    --- extra `l` layer: `<localleader>l` compiles, `<localleader>c` cleans.
    prefix = '<localleader>',
    --- Motions: ]] [[ ][ [] ]m [m ]n [n ]r [r ]/ [/ and %
    motions = true,
    --- Text objects: ae/ie ac/ic a$/i$ ad/id am/im aP/iP
    text_objects = true,
    --- ds*/cs*/ts* delete, change and toggle mappings plus <F6>/<F7>.
    surround = true,
    --- `K` opens package documentation via `texdoc`.
    doc_package = true,
  },
}

---@type table
M.options = vim.deepcopy(M.defaults)

---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  -- `vim.tbl_deep_extend` merges list-like tables key by key, which would keep
  -- stale trailing entries. For the lists users realistically replace we take
  -- the user value verbatim.
  local user = opts or {}
  if vim.tbl_get(user, 'compiler', 'latexmk', 'options') then
    M.options.compiler.latexmk.options = user.compiler.latexmk.options
  end
  if vim.tbl_get(user, 'qf', 'ignore_filters') then
    M.options.qf.ignore_filters = user.qf.ignore_filters
  end
  if vim.tbl_get(user, 'filetypes') then
    M.options.filetypes = user.filetypes
  end
  return M.options
end

--- Convenience accessor: `config.get('compiler', 'latexmk', 'executable')`.
function M.get(...)
  if select('#', ...) == 0 then
    return M.options
  end
  return vim.tbl_get(M.options, ...)
end

return M
