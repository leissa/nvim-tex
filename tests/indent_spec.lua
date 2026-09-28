local H = require('tests.helpers')
local indent = require('nvim-tex.indent')

--- Strip the indentation from `expected`, reindent the buffer with `gg=G`
--- and hand back what came out.
---@param expected string[]
---@return string[]
local function reindent(expected)
  local flat = vim.tbl_map(function(line)
    return (line:gsub('^%s+', ''))
  end, expected)
  local bufnr = H.buf(flat)
  vim.bo[bufnr].shiftwidth = 2
  vim.bo[bufnr].expandtab = true
  indent.attach(bufnr)
  vim.cmd('silent normal! gg=G')
  return H.lines(bufnr)
end

--- `gg=G` on the unindented form of `lines` gives `lines` back.
---@param lines string[]
local function roundtrip(lines)
  T.eq(lines, reindent(lines))
end

--- Type `keys` in insert mode into a buffer holding `lines`, with the cursor
--- at the end of the last line, the way a user would.
---@param lines string[]
---@param keys string
---@return string[]
local function typed(lines, keys)
  local bufnr = H.buf(lines)
  vim.bo[bufnr].shiftwidth = 2
  vim.bo[bufnr].expandtab = true
  indent.attach(bufnr)
  H.cursor(#lines, 0)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('A' .. keys .. '<Esc>', true, false, true), 'xt', false)
  return H.lines(bufnr)
end

describe('indent', function()
  before_each(H.need_parser)
  after_each(H.cleanup)

  it('indents an environment body', function()
    roundtrip({
      '\\begin{center}',
      '  text',
      '  \\begin{tabular}{ll}',
      '    a & b \\\\',
      '  \\end{tabular}',
      '\\end{center}',
    })
  end)

  it('leaves the document body where it is', function()
    roundtrip({
      '\\documentclass{article}',
      '\\begin{document}',
      '\\section{Intro}',
      'text',
      '\\end{document}',
    })
  end)

  it('indents items and, one level further, their continuation lines', function()
    roundtrip({
      '\\begin{itemize}',
      '  \\item one',
      '    more of one',
      '  \\item two',
      '    \\begin{enumerate}',
      '      \\item nested',
      '        more',
      '    \\end{enumerate}',
      '  \\item three',
      '\\end{itemize}',
    })
  end)

  it('treats \\bibitem as an item', function()
    roundtrip({
      '\\begin{thebibliography}{9}',
      '  \\bibitem{knuth} D. Knuth,',
      '    The TeXbook.',
      '\\end{thebibliography}',
    })
  end)

  it('indents multi-line groups and option lists', function()
    roundtrip({
      '\\newcommand{\\foo}{%',
      '  \\textbf{bar}%',
      '}',
      '\\usepackage[',
      '  margin=1in,',
      ']{geometry}',
      '\\begin{tikzpicture}[',
      '    scale=2,',
      '  ]',
      '  \\draw (0,0) -- (1,1);',
      '\\end{tikzpicture}',
    })
  end)

  it('indents display math and \\left ... \\right', function()
    roundtrip({
      '\\[',
      '  f(x) = \\left(',
      '    \\frac{a}{b}',
      '  \\right)',
      '\\]',
      '\\begin{align}',
      '  a &= b \\\\',
      '  c &= d',
      '\\end{align}',
    })
  end)

  it('is not fooled by escaped braces, comments or brackets in math', function()
    roundtrip({
      '\\begin{center}',
      '  $\\{ x \\mid x \\in [0, 1) \\}$ % {',
      '  after',
      '\\end{center}',
    })
  end)

  it('keeps the indentation inside verbatim environments', function()
    local lines = {
      '\\begin{center}',
      '  \\begin{verbatim}',
      'if (x) {',
      '      y;',
      '  \\end{verbatim}',
      '\\end{center}',
    }
    local bufnr = H.buf(lines)
    vim.bo[bufnr].shiftwidth = 2
    indent.attach(bufnr)
    T.eq(-1, indent.get(3, bufnr))
    T.eq(-1, indent.get(4, bufnr))
    T.eq(2, indent.get(5, bufnr))
  end)

  it('honours the configured list environments', function()
    require('nvim-tex.config').setup({ indent = { lists = { 'steps' } } })
    roundtrip({
      '\\begin{steps}',
      '  \\item one',
      '\\end{steps}',
      '\\begin{itemize}',
      '\\item one',
      '  more',
      '\\end{itemize}',
    })
  end)

  it('indents the lines that continue a TikZ statement', function()
    roundtrip({
      '\\begin{tikzpicture}',
      '  \\draw[->] (a)',
      '    -- node[above] {$\\alpha$} (b)',
      '    % comment',
      '    -- (c);',
      '  \\draw (a) -- (b) {',
      '    text',
      '  }',
      '    -- (c) node {',
      '      d',
      '    };',
      '  \\foreach \\i in {1,...,3} {',
      '    \\fill (\\i,0)',
      '      circle (2pt);',
      '  }',
      '  \\tikzset{a/.style={b}}',
      '  \\begin{scope}',
      '    \\draw (0,0)',
      '      -- (1,1);',
      '  \\end{scope}',
      '\\end{tikzpicture}',
    })
  end)

  it('leaves the same lines alone outside a picture', function()
    roundtrip({
      '\\begin{center}',
      '  \\draw (a)',
      '  -- (b);',
      '\\end{center}',
    })
  end)

  describe('while typing', function()
    it('indents the line after a \\begin that has no \\end yet', function()
      T.eq({ '\\begin{center}', '  x' }, typed({ '\\begin{center}' }, '<CR>x'))
    end)

    it('puts the first \\item of a new list one level in', function()
      T.eq({ '\\begin{itemize}', '  \\item a' }, typed({ '\\begin{itemize}' }, '<CR>\\item a'))
    end)

    it('lines a continuation up under the item and the next item with it', function()
      T.eq(
        { '\\begin{itemize}', '  \\item a', '    b', '  \\item c' },
        typed({ '\\begin{itemize}', '  \\item a' }, '<CR>b<CR>\\item c')
      )
    end)

    it('dedents \\end as it is typed', function()
      T.eq(
        { '\\begin{itemize}', '  \\item a', '\\end{itemize}' },
        typed({ '\\begin{itemize}', '  \\item a' }, '<CR>\\end{itemize}')
      )
    end)

    it('continues a TikZ path until its ;', function()
      local bufnr = H.buf({ '\\begin{tikzpicture}', '\\end{tikzpicture}' })
      vim.bo[bufnr].shiftwidth = 2
      vim.bo[bufnr].expandtab = true
      indent.attach(bufnr)
      H.cursor(1, 0)
      local keys = 'o\\draw (a)<CR>-- (b);<CR>\\fill<Esc>'
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
      T.eq({ '\\begin{tikzpicture}', '  \\draw (a)', '    -- (b);', '  \\fill', '\\end{tikzpicture}' }, H.lines(bufnr))
    end)

    it('dedents a closing brace as it is typed', function()
      T.eq({ '\\foo{', '  a', '}' }, typed({ '\\foo{' }, '<CR>a<CR>}'))
    end)
  end)
end)
