local H = require('tests.helpers')
local injections = require('nvim-tex.injections')

describe('injections', function()
  after_each(H.cleanup)

  describe('parse_options', function()
    it('finds the language and the length of the options', function()
      T.eq({ 'python', 17 }, { injections.parse_options('[language=Python]\nprint(1)\n') })
    end)

    it('finds it among other options, braced, with a dialect', function()
      T.eq('cpp', (injections.parse_options('[caption=x, language=C++]')))
      T.eq('c', (injections.parse_options('[language={[ANSI]C}]')))
      T.eq('bash', (injections.parse_options('[ language = sh ,numbers=left]')))
    end)

    it('has nothing to say without options or without a language', function()
      T.eq(nil, (injections.parse_options('print(1)')))
      T.eq(nil, (injections.parse_options('[caption=x]')))
    end)
  end)

  it('injects the language of an lstlisting, starting after the options', function()
    H.need_parser()
    local path = vim.fs.joinpath(vim.fn.stdpath('data'), 'site', 'parser', 'python.so')
    if
      not pcall(vim.treesitter.language.add, 'python', { path = path })
      or not pcall(vim.treesitter.get_string_parser, '', 'python')
    then
      T.skip('the python parser is not installed')
    end
    local bufnr = H.buf({
      '\\begin{lstlisting}[language=Python]',
      'print(1)',
      '\\end{lstlisting}',
    })
    local parser = vim.treesitter.get_parser(bufnr, 'latex')
    parser:parse(true)
    local python = parser:children().python
    T.ok(python, 'no python injection')
    local ranges = python:included_regions()
    local first = ranges[1] and ranges[1][1]
    T.eq({ 0, 35 }, { first[1], first[2] })
  end)
end)
