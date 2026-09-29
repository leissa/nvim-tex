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
    --- 'latexmk' or 'tectonic'. The options of the active backend live in
    --- the table of the same name below.
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
      --- An empty `aux_dir` follows `out_dir`, as latexmk itself does.
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

    tectonic = {
      executable = 'tectonic',
      --- Tectonic reruns the engine and BibTeX itself and has no watch mode
      --- for a plain file, so every compilation is a single shot; combine it
      --- with `build_on_save` for a continuous feel.
      options = {
        '--synctex',
        '--keep-logs',
      },
      --- Relative to the main file's directory. Tectonic has no separate aux
      --- directory: the log lands next to the PDF.
      out_dir = '',
      --- Extra extensions for `:TexClean`, space separated, no leading dot.
      clean_ext = '',
      --- Functions called with every line of compiler output.
      hooks = {},
    },
  },

  view = {
    enabled = true,
    --- 'auto' picks the first available of zathura, sioyek, okular, skim,
    --- general. Set explicitly to override.
    method = 'auto',
    --- Jump to the cursor position in the PDF right after opening the viewer.
    forward_search_on_start = true,
    --- Show compiled fragments (`:TexTikzPreview`, `:TexCompileSelected`)
    --- below their last line with snacks.nvim's image support, when it is
    --- enabled and the terminal can show images, instead of in the viewer.
    snacks = {
      enabled = true,
      --- Magnification over the fragment's printed size.
      scale = 2,
    },

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
    --- Also open it when there are only warnings (no errors). Info-level
    --- messages never open the window on their own.
    open_on_warning = true,
    --- Lowest severity shown in the quickfix list: 'error', 'warning' or
    --- 'info'. A LaTeX run narrates most of what it does -- font
    --- substitutions, package infos -- and that chatter is classified as
    --- 'info' and hidden by default. `:TexQfLevel` cycles the level without
    --- recompiling.
    level = 'warning',
    --- Collect over/underfull box warnings. They are a typesetting detail
    --- rather than a defect and outnumber everything else in a real log, so
    --- they are dropped outright by default -- no level shows them.
    boxes = false,
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
  },

  --- Folding through `vim.treesitter.foldexpr()`, with a `folds` query
  --- built from these options. Needs the `latex` parser.
  fold = {
    enabled = false,
    --- From `\documentclass` to the line before `\begin{document}`.
    preamble = true,
    --- Parts, chapters, sections, ... down to subparagraphs, nested.
    sections = true,
    --- Multi-line environments, verbatim ones included.
    envs = true,
    --- Environments that never fold.
    ignored_envs = { 'document' },
    --- `\[ ... \]` and `$$ ... $$`.
    math = true,
    --- `\begin{comment}` and `\iffalse ... \fi` blocks.
    comments = true,
  },

  --- Conceal (VimTeX's syntax conceal, from the parse tree). Shows only
  --- with 'conceallevel' at 1 or 2, which nvim-tex leaves to you.
  conceal = {
    enabled = true,
    --- `\alpha` -> α, in math.
    greek = true,
    --- `\leq` -> ≤, `\to` -> →, `\sum` -> ∑, ..., in math.
    math_symbols = true,
    --- `\mathbb{R}` -> ℝ, `\mathcal{A}` -> 𝒜, `\mathfrak{g}` -> 𝔤.
    math_fonts = true,
    --- `x^2` -> x², `a_{ij}` -> aᵢⱼ, when every character has a form.
    math_super_sub = true,
    --- Hide `\left`, `\right`, `\bigl`, ...
    math_delimiters = true,
    --- `\'e` -> é, `\"{a}` -> ä, `\c c` -> ç.
    accents = true,
    --- `\ss` -> ß, `\dots` -> …, `\S` -> §, ...
    text_symbols = true,
    --- `--` -> –, `---` -> —, ``` ``quoted'' ``` -> “quoted”.
    ligatures = true,
    --- `\,`, `\quad` and friends -> a space.
    spacing = true,
    --- `\textbf{x}` -> x in bold; also `\textit`, `\emph`, `\underline`.
    styles = true,
    --- `\cite{key}` -> [key].
    cites = true,
    --- `\item` -> •.
    item = true,
    --- Your own commands, e.g. `{ ['\\R'] = 'ℝ' }`, in text and math.
    custom = {},
  },

  --- `:TexCountWords` and `:TexCountLetters`.
  texcount = {
    executable = 'texcount',
    --- Extra flags, appended to the ones nvim-tex passes itself: for example
    --- `{ '-incbib' }` to count the bibliography too.
    options = {},
  },

  --- `:TexCite`: search online, add the entry to the bibliography, cite it.
  cite = {
    --- DBLP, searched through its SPARQL endpoint.
    dblp = {
      enabled = true,
      endpoint = 'https://sparql.dblp.org/sparql',
      max_results = 30,
    },
    --- Key of a new entry: 'short' for `leissa2015graph`, 'source' for the
    --- source's own (`DBLP:conf/cgo/LeissaKH15`), or a function(entry)
    --- returning one.
    key = 'short',
    --- Offer the key for editing before the entry is added.
    edit_key = true,
    --- Downloads go through curl, as a string or list.
    curl = 'curl',
    --- Seconds per request.
    timeout = 20,
  },

  --- LaTeX-aware indentation through `indentexpr`. Needs the `latex` parser.
  indent = {
    enabled = true,
    --- List environments: `\item` is indented one level into them, and the
    --- lines that continue an item one level further.
    lists = { 'itemize', 'enumerate', 'description', 'thebibliography' },
    --- Environments whose body is not indented.
    ignored_envs = { 'document' },
  },

  --- TikZ pictures: the statements `a;`/`i;` select, `];`/`[;` jump to and
  --- indentation continues.
  tikz = {
    --- Environments whose body is a list of TikZ statements.
    environments = { 'tikzpicture', 'circuitikz' },
    --- Commands, without the backslash, that start a path running to the
    --- next `;`. Any other command at the start of a statement is a
    --- statement of its own, with the braced arguments that follow it:
    --- `\tikzset{...}`, `\pgfmathsetmacro{\x}{1}`.
    path_commands = {
      'path',
      'draw',
      'fill',
      'filldraw',
      'pattern',
      'shade',
      'shadedraw',
      'clip',
      'useasboundingbox',
      'node',
      'coordinate',
      'pic',
      'matrix',
      'graph',
      'datavisualization',
      'calendar',
      'chainin',
      'spy',
      'addplot',
      'addplot3',
    },
    --- Complete node and style names with `<C-x><C-u>`: set 'completefunc',
    --- unless something else already has.
    completefunc = true,
    --- `:TexTikzPreview` compiles the picture under the cursor on its own.
    preview = {
      --- Commands, without the backslash, copied from the document body
      --- before the picture, besides `\newcommand`, `\def` and the other
      --- definitions.
      commands = {
        'tikzset',
        'tikzstyle',
        'pgfmathsetmacro',
        'pgfmathtruncatemacro',
        'pgfmathsetlengthmacro',
        'pgfplotsset',
        'pgfkeys',
        'pgfdeclarelayer',
        'pgfsetlayers',
        'colorlet',
        'definecolor',
        'newlength',
        'setlength',
        'usepgfplotslibrary',
      },
      --- Read the main document's `.aux`, so `\ref` and `\cite` resolve.
      aux = true,
      --- Space around the cropped picture.
      border = '2pt',
    },
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

  --- Insert mode math mappings (vimtex's `imaps`). See `nvim-tex.imaps`.
  imaps = {
    enabled = true,
    --- Typed before the `lhs` of every entry that does not bring its own.
    leader = '`',
    --- `lhs` values from `list` to leave unmapped.
    disabled = {},
    --- Every entry is `{ lhs, rhs, leader, style, wrapper }`:
    ---   `rhs`     the text to insert, or a function returning it.
    ---   `style`   shorthand for "read one more character and wrap it in
    ---             this command": `#bx` gives `\mathbf{x}`.
    ---   `leader`  overrides `leader` for this entry.
    ---   `wrapper` when the expansion happens: `'math'` (the default) only
    ---             inside a math zone, `'trivial'` always. A
    ---             function(lhs, expand) may be given instead.
    --- Entries can also be added one at a time with `imaps.add`.
    list = {
      { lhs = '0', rhs = '\\emptyset' },
      { lhs = '2', rhs = '\\sqrt' },
      { lhs = '6', rhs = '\\partial' },
      { lhs = '8', rhs = '\\infty' },
      { lhs = '=', rhs = '\\equiv' },
      { lhs = '\\', rhs = '\\setminus' },
      { lhs = '.', rhs = '\\cdot' },
      { lhs = '*', rhs = '\\times' },
      { lhs = '+', rhs = '\\dagger' },
      { lhs = '<', rhs = '\\langle' },
      { lhs = '>', rhs = '\\rangle' },
      { lhs = '[', rhs = '\\subseteq' },
      { lhs = ']', rhs = '\\supseteq' },
      { lhs = '(', rhs = '\\subset' },
      { lhs = ')', rhs = '\\supset' },
      { lhs = 'A', rhs = '\\forall' },
      { lhs = 'B', rhs = '\\boldsymbol' },
      { lhs = 'E', rhs = '\\exists' },
      { lhs = 'H', rhs = '\\hbar' },
      { lhs = 'N', rhs = '\\nabla' },

      -- Arrows: `j` plus a direction, shifted for the double stroke.
      { lhs = 'jh', rhs = '\\leftarrow' },
      { lhs = 'jH', rhs = '\\Leftarrow' },
      { lhs = 'jj', rhs = '\\downarrow' },
      { lhs = 'jJ', rhs = '\\Downarrow' },
      { lhs = 'jk', rhs = '\\uparrow' },
      { lhs = 'jK', rhs = '\\Uparrow' },
      { lhs = 'jl', rhs = '\\rightarrow' },
      { lhs = 'jL', rhs = '\\Rightarrow' },

      -- Greek, lower case.
      { lhs = 'a', rhs = '\\alpha' },
      { lhs = 'b', rhs = '\\beta' },
      { lhs = 'c', rhs = '\\chi' },
      { lhs = 'd', rhs = '\\delta' },
      { lhs = 'e', rhs = '\\epsilon' },
      { lhs = 'f', rhs = '\\phi' },
      { lhs = 'g', rhs = '\\gamma' },
      { lhs = 'h', rhs = '\\eta' },
      { lhs = 'i', rhs = '\\iota' },
      { lhs = 'k', rhs = '\\kappa' },
      { lhs = 'l', rhs = '\\lambda' },
      { lhs = 'm', rhs = '\\mu' },
      { lhs = 'n', rhs = '\\nu' },
      { lhs = 'p', rhs = '\\pi' },
      { lhs = 'q', rhs = '\\theta' },
      { lhs = 'r', rhs = '\\rho' },
      { lhs = 's', rhs = '\\sigma' },
      { lhs = 't', rhs = '\\tau' },
      { lhs = 'u', rhs = '\\upsilon' },
      { lhs = 'w', rhs = '\\omega' },
      { lhs = 'x', rhs = '\\xi' },
      { lhs = 'y', rhs = '\\psi' },
      { lhs = 'z', rhs = '\\zeta' },

      -- Greek, upper case. The letters that would collide with a symbol
      -- above (`A`, `B`, `E`, `H`, `N`) are left to the symbol.
      { lhs = 'D', rhs = '\\Delta' },
      { lhs = 'F', rhs = '\\Phi' },
      { lhs = 'G', rhs = '\\Gamma' },
      { lhs = 'L', rhs = '\\Lambda' },
      { lhs = 'P', rhs = '\\Pi' },
      { lhs = 'Q', rhs = '\\Theta' },
      { lhs = 'S', rhs = '\\Sigma' },
      { lhs = 'U', rhs = '\\Upsilon' },
      { lhs = 'W', rhs = '\\Omega' },
      { lhs = 'X', rhs = '\\Xi' },
      { lhs = 'Y', rhs = '\\Psi' },

      -- Greek variants, behind a `v`.
      { lhs = 've', rhs = '\\varepsilon' },
      { lhs = 'vf', rhs = '\\varphi' },
      { lhs = 'vk', rhs = '\\varkappa' },
      { lhs = 'vp', rhs = '\\varpi' },
      { lhs = 'vq', rhs = '\\vartheta' },
      { lhs = 'vr', rhs = '\\varrho' },

      -- Styles, behind their own leader: `#` , a style key, and the
      -- character to wrap.
      { leader = '#', lhs = '-', style = 'overline' },
      { leader = '#', lhs = '/', style = 'slashed' },
      { leader = '#', lhs = 'b', style = 'mathbf' },
      { leader = '#', lhs = 'B', style = 'mathbb' },
      { leader = '#', lhs = 'c', style = 'mathcal' },
      { leader = '#', lhs = 'f', style = 'mathfrak' },

      -- Two backticks open a quotation in LaTeX, so the leader typed twice
      -- inserts them, in math and in text alike.
      { lhs = '`', rhs = '``', wrapper = 'trivial' },
    },
  },

  mappings = {
    enabled = true,
    --- `<localleader>` is already buffer-local, so unlike vimtex there is no
    --- extra `l` layer: `<localleader>l` compiles, `<localleader>c` cleans.
    prefix = '<localleader>',
    --- Motions: ]] [[ ][ [] ]m [m ]n [n ]r [r ]/ [/ ]; [; and %
    motions = true,
    --- Text objects: ae/ie ac/ic a$/i$ ad/id am/im aP/iP a;/i;
    text_objects = true,
    --- ds*/cs*/ts* delete, change and toggle mappings plus <F6>/<F7>.
    surround = true,
    --- `K` opens package documentation via `texdoc`.
    doc_package = true,
  },
}

---@type table
M.options = vim.deepcopy(M.defaults)

--- Lists users realistically replace. `vim.tbl_deep_extend` merges
--- list-like tables key by key, which would keep stale trailing entries, so
--- for these the user value is taken verbatim.
local LISTS = {
  { 'filetypes' },
  { 'compiler', 'latexmk', 'options' },
  { 'compiler', 'tectonic', 'options' },
  { 'texcount', 'options' },
  { 'qf', 'ignore_filters' },
  { 'fold', 'ignored_envs' },
  { 'indent', 'lists' },
  { 'indent', 'ignored_envs' },
  { 'tikz', 'environments' },
  { 'tikz', 'path_commands' },
  { 'tikz', 'preview', 'commands' },
  { 'imaps', 'list' },
  { 'imaps', 'disabled' },
}

---@param opts table|nil
function M.setup(opts)
  local user = opts or {}
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), user)
  for _, path in ipairs(LISTS) do
    local value = vim.tbl_get(user, unpack(path))
    if value then
      local parent = vim.tbl_get(M.options, unpack(path, 1, #path - 1)) or M.options
      parent[path[#path]] = value
    end
  end
  return M.options
end

--- The options table of the active compiler backend,
--- `compiler[compiler.method]`.
---@return table
function M.compiler_options()
  local compiler = M.options.compiler or {}
  return compiler[compiler.method] or {}
end

--- Convenience accessor: `config.get('compiler', 'latexmk', 'executable')`.
function M.get(...)
  if select('#', ...) == 0 then
    return M.options
  end
  return vim.tbl_get(M.options, ...)
end

return M
