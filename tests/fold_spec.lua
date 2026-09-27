local H = require('tests.helpers')
local config = require('nvim-tex.config')
local fold = require('nvim-tex.fold')

--- The `foldexpr` value of every line of `lines`, with folding set up by
--- nvim-tex. `vim.treesitter.foldexpr` computes levels asynchronously in
--- newer Neovim versions, hence the wait.
---@param lines string[]
---@param opts table|nil `fold` configuration
---@return string[]
local function levels(lines, opts)
  config.setup({ fold = vim.tbl_extend('force', { enabled = true }, opts or {}) })
  local bufnr = H.buf(lines)
  fold.attach(bufnr)
  local function collect()
    local out = {}
    for lnum = 1, #lines do
      out[lnum] = tostring(vim.treesitter.foldexpr(lnum))
    end
    return out
  end
  collect()
  local out
  vim.wait(300, function()
    out = collect()
    return vim.iter(out):any(function(level)
      return level ~= '0'
    end)
  end, 10)
  return out
end

local DOC = {
  '\\documentclass{article}', --  1
  '\\usepackage{amsmath}', --  2
  '', --  3
  '\\begin{document}', --  4
  '\\section{One}', --  5
  'text', --  6
  '\\begin{figure}', --  7
  'x', --  8
  '\\end{figure}', --  9
  '', -- 10
  '\\subsection{Sub}', -- 11
  '\\[', -- 12
  'a', -- 13
  '\\]', -- 14
  '', -- 15
  '\\section{Two}', -- 16
  'more', -- 17
  '\\end{document}', -- 18
}

describe('fold', function()
  before_each(H.need_parser)
  after_each(H.cleanup)

  it('folds the preamble, sections, environments and display math', function()
    T.eq({
      '>1', -- preamble
      '1',
      '1',
      '0', -- \begin{document} does not fold
      '>1', -- \section{One}
      '1',
      '>2', -- figure
      '2',
      '2',
      '1',
      '>2', -- \subsection{Sub}, nested in the section
      '>3', -- \[
      '3',
      '3',
      '2', -- the blank line folds with the subsection
      '>1', -- \section{Two}, a fold of its own
      '1',
      '0', -- \end{document}
    }, levels(DOC))
  end)

  it('leaves out what is switched off', function()
    local out = levels(DOC, { preamble = false, envs = false, math = false })
    T.eq('0', out[1])
    T.eq('1', out[7])
    T.eq('2', out[12])
  end)

  it('folds document too once it is no longer ignored', function()
    local out = levels(DOC, { ignored_envs = {} })
    T.eq('>1', out[4])
    T.eq('>2', out[5])
  end)

  it('folds verbatim and comment environments', function()
    local out = levels({
      '\\begin{verbatim}',
      'x',
      '\\end{verbatim}',
      '\\begin{comment}',
      'y',
      '\\end{comment}',
    })
    T.eq({ '>1', '1', '1', '>1', '1', '1' }, out)
  end)

  it('skips an ignored environment with a starred name too', function()
    local out = levels({ '\\begin{mine*}', 'x', '\\end{mine*}' }, { ignored_envs = { 'mine' } })
    T.eq({ '0', '0', '0' }, out)
  end)
end)
