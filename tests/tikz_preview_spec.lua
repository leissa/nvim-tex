local H = require('tests.helpers')
local config = require('nvim-tex.config')
local preview = require('nvim-tex.tikz.preview')
local tikz = require('nvim-tex.tikz')
local ts = require('nvim-tex.ts')

local BODY = {
  '\\begin{document}',
  '\\newcommand{\\Bar}{bar}',
  '\\def\\baz{BAZ}',
  '\\begin{figure}',
  '  \\tikzset{hot/.style={fill=red}}',
  '  \\tikzstyle{cold}=[fill=blue]',
  '  \\label{fig:x}',
  '  \\begin{tikzpicture}',
  '    \\node[hot] {\\Bar};',
  '  \\end{tikzpicture}',
  '\\end{figure}',
  '\\newcommand{\\after}{no}',
  '\\end{document}',
}

--- A main file with `preamble` and `BODY` on disk and in a buffer, the
--- cursor in the picture, and the preview document for it.
---@param preamble string[]
---@param aux string|nil contents of the main `.aux`
---@return string[]|nil, string|nil
local function document(preamble, aux)
  local dir = H.tmpdir()
  local main = dir .. '/main.tex'
  local lines = vim.list_extend(vim.list_extend({}, preamble), BODY)
  H.write(main, table.concat(lines, '\n'))
  if aux then
    H.write(dir .. '/main.aux', aux)
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(main))
  local bufnr = vim.api.nvim_get_current_buf()
  H.cursor_at('node[hot]')
  local picture = tikz.picture(ts.node_at_cursor(bufnr), bufnr)
  return preview.document(H.project(main), bufnr, picture)
end

describe('tikz preview', function()
  before_each(H.need_parser)
  after_each(function()
    config.setup({})
    vim.cmd('silent! %bwipeout!')
    H.cleanup()
  end)

  it('sets the picture in the preamble, cropped, with the definitions before it', function()
    T.eq({
      '\\documentclass{article}',
      '\\usepackage{tikz}',
      '\\makeatletter',
      '\\@ifpackageloaded{preview}{}{\\usepackage[active,tightpage]{preview}}',
      '\\makeatother',
      '\\PreviewEnvironment{tikzpicture}',
      '\\setlength\\PreviewBorder{2pt}',
      '\\newcommand{\\Bar}{bar}',
      '\\def\\baz{BAZ}',
      '\\tikzset{hot/.style={fill=red}}',
      '\\tikzstyle{cold}=[fill=blue]',
      '\\begin{document}',
      '\\begin{tikzpicture}',
      '    \\node[hot] {\\Bar};',
      '  \\end{tikzpicture}',
      '\\end{document}',
    }, document({ '\\documentclass{article}', '\\usepackage{tikz}' }))
  end)

  it('leaves the cropping to a standalone class', function()
    local lines = document({ '\\documentclass[tikz]{standalone}' })
    T.eq(false, vim.tbl_contains(lines, '\\PreviewEnvironment{tikzpicture}'))
  end)

  it('reads the main .aux at the start of the document', function()
    local lines = document({ '\\documentclass{article}' }, '\\relax')
    local aux = vim.tbl_filter(function(line)
      return line:find('main.aux', 1, true) ~= nil
    end, lines)
    T.eq(1, #aux)
    T.matches('^\\makeatletter\\AtBeginDocument{\\makeatletter\\@input{.*/main%.aux}', aux[1])

    config.setup({ tikz = { preview = { aux = false } } })
    lines = document({ '\\documentclass{article}' }, '\\relax')
    T.eq(
      {},
      vim.tbl_filter(function(line)
        return line:find('main.aux', 1, true) ~= nil
      end, lines)
    )
  end)

  it('needs a \\begin{document} in the main file', function()
    local dir = H.tmpdir()
    H.write(dir .. '/main.tex', '\\input{fig}')
    H.buf({ '\\begin{tikzpicture}', '\\draw (0,0);', '\\end{tikzpicture}' })
    local bufnr = vim.api.nvim_get_current_buf()
    local lines, err =
      preview.document(H.project(dir .. '/main.tex'), bufnr, tikz.picture(ts.node_at_cursor(bufnr, { 2, 0 }), bufnr))
    T.eq(nil, lines)
    T.matches('no \\begin{document}', err)
  end)
end)
