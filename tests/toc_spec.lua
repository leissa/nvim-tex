local H = require('tests.helpers')
local config = require('nvim-tex.config')
local toc = require('nvim-tex.toc')

--- The titles of the entries built for a project rooted at `main`.
---@param entries table[]
---@return string[]
local function titles(entries)
  return vim.tbl_map(function(entry)
    return entry.title
  end, entries)
end

describe('toc', function()
  before_each(H.need_parser)
  after_each(H.cleanup)

  it('lists the sectioning commands with their levels', function()
    local dir = H.tmpdir()
    local main = H.write(dir .. '/main.tex', {
      '\\documentclass{book}',
      '\\begin{document}',
      '\\chapter{First}',
      '\\section{One}',
      '\\subsection{Deeper}',
      '\\end{document}',
    })
    local entries = toc.build(H.project(main))
    T.eq({ 'First', 'One', 'Deeper' }, titles(entries))
    T.eq({ 1, 2, 3 }, vim.tbl_map(function(entry)
      return entry.level
    end, entries))
    T.eq(3, entries[1].lnum)
  end)

  it('strips markup from a title', function()
    local dir = H.tmpdir()
    local main = H.write(dir .. '/main.tex', { '\\section{A \\emph{fancy} title}' })
    T.eq({ 'A fancy title' }, titles(toc.build(H.project(main))))
  end)

  it('follows \\input into another file', function()
    local dir = H.tmpdir()
    H.write(dir .. '/chapters/intro.tex', { '\\section{From the include}' })
    local main = H.write(dir .. '/main.tex', {
      '\\documentclass{book}',
      '\\input{chapters/intro}',
      '\\section{Back in the main file}',
    })
    local entries = toc.build(H.project(main))
    T.eq({
      'include: chapters/intro',
      'From the include',
      'Back in the main file',
    }, titles(entries))
    T.eq(dir .. '/chapters/intro.tex', entries[2].file)
  end)

  it('can leave the include markers out', function()
    config.setup({ toc = { show_includes = false } })
    local dir = H.tmpdir()
    H.write(dir .. '/intro.tex', { '\\section{From the include}' })
    local main = H.write(dir .. '/main.tex', { '\\input{intro}' })
    T.eq({ 'From the include' }, titles(toc.build(H.project(main))))
  end)

  it('does not loop on a file that includes itself', function()
    local dir = H.tmpdir()
    local main = H.write(dir .. '/main.tex', { '\\input{main}', '\\section{One}' })
    T.eq({ 'include: main', 'One' }, titles(toc.build(H.project(main))))
  end)

  it('collects TODO comments', function()
    local dir = H.tmpdir()
    local main = H.write(dir .. '/main.tex', {
      '\\section{One}',
      '% TODO rewrite this',
      '% FIXME and this',
      '% just a comment',
    })
    T.eq({ 'One', 'TODO rewrite this', 'FIXME and this' }, titles(toc.build(H.project(main))))
  end)

  it('can leave the TODO comments out', function()
    config.setup({ toc = { show_todos = false } })
    local dir = H.tmpdir()
    local main = H.write(dir .. '/main.tex', { '\\section{One}', '% TODO rewrite this' })
    T.eq({ 'One' }, titles(toc.build(H.project(main))))
  end)

  it('collects labels only when asked to', function()
    local dir = H.tmpdir()
    local main = H.write(dir .. '/main.tex', { '\\section{One}', '\\label{sec:one}' })
    T.eq({ 'One' }, titles(toc.build(H.project(main))))

    config.setup({ toc = { show_labels = true } })
    T.eq({ 'One', 'label: sec:one' }, titles(toc.build(H.project(main))))
  end)

  it('lists beamer frames by their title', function()
    local dir = H.tmpdir()
    local main = H.write(dir .. '/main.tex', {
      '\\begin{frame}{The title}',
      'content',
      '\\end{frame}',
      '\\begin{frame}',
      'content',
      '\\end{frame}',
    })
    T.eq({ 'frame: The title', 'frame: (untitled)' }, titles(toc.build(H.project(main))))
  end)

  it('prefers the contents of a loaded buffer over the file on disk', function()
    local dir = H.tmpdir()
    local main = H.write(dir .. '/main.tex', { '\\section{On disk}' })
    H.buf({ '\\section{In the buffer}' }, { name = main })
    T.eq({ 'In the buffer' }, titles(toc.build(H.project(main))))
  end)

  it('is empty for a file that is not there', function()
    T.eq({}, toc.build(H.project('/nonexistent/nvim-tex/main.tex')))
  end)

  describe('window', function()
    it('opens a listing and closes again', function()
      local dir = H.tmpdir()
      local main = H.write(dir .. '/main.tex', { '\\section{One}', '\\section{Two}' })
      local project = H.project(main)

      toc.open(project)
      local winid = toc.window()
      T.ok(winid)
      -- Entries are rendered with two spaces of indentation per level.
      T.eq(
        { '    One', '    Two' },
        vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(winid), 0, -1, false)
      )

      toc.toggle(project)
      T.eq(nil, toc.window())
    end)
  end)
end)
