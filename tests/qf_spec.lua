local H = require('tests.helpers')
local config = require('nvim-tex.config')
local qf = require('nvim-tex.qf')

--- Parse `lines` as a `.log` file sitting in a fresh temporary directory.
---@param lines string[]
---@return table[] items, string root, string main
local function parse(lines)
  local root = H.tmpdir()
  local log = H.write(root .. '/main.log', lines)
  return qf.parse_log(log, root, root .. '/main.tex'), root, root .. '/main.tex'
end

describe('qf', function()
  after_each(H.cleanup)

  describe('parse_log', function()
    it('reads the -file-line-error format', function()
      local items, root = parse({
        './main.tex:12: Undefined control sequence.',
      })
      T.eq(1, #items)
      T.eq('E', items[1].type)
      T.eq(12, items[1].lnum)
      T.eq(root .. '/main.tex', items[1].filename)
      T.eq('Undefined control sequence.', items[1].text)
    end)

    it('keeps an absolute file name as it is', function()
      local items = parse({ '/elsewhere/other.tex:3: Boom.' })
      T.eq('/elsewhere/other.tex', items[1].filename)
    end)

    it('reads a plain TeX error and picks the line up from the l.N line', function()
      local items = parse({
        '! Undefined control sequence.',
        'l.42 \\nosuchmacro',
      })
      T.eq(1, #items)
      T.eq('E', items[1].type)
      T.eq(42, items[1].lnum)
      T.eq('Undefined control sequence.', items[1].text)
    end)

    it('reports a plain TeX error without an l.N line at line 0', function()
      local items = parse({ '! Emergency stop.' })
      T.eq(0, items[1].lnum)
    end)

    it('folds a warning continuation line into the message', function()
      local items = parse({
        'LaTeX Warning: Reference `sec:intro\' on page 1 undefined on input line 7.',
      })
      T.eq(1, #items)
      T.eq('W', items[1].type)
      T.eq(7, items[1].lnum)
      -- The line number has its own quickfix column, so it is stripped.
      T.falsy(items[1].text:find('on input line'))
    end)

    it('strips the (package) prefix from a continuation line', function()
      local items = parse({
        'Package biblatex Warning: Please rerun LaTeX.',
        '(biblatex)                on input line 91.',
      })
      T.eq(1, #items)
      T.eq(91, items[1].lnum)
      T.eq('Package biblatex Warning: Please rerun LaTeX.', items[1].text)
    end)

    it('folds an indented continuation line', function()
      local items = parse({
        'LaTeX Warning: Something happened',
        '  and here is the rest on input line 5.',
      })
      T.eq(1, #items)
      T.eq(5, items[1].lnum)
      T.matches('here is the rest', items[1].text)
    end)

    it('does not swallow the message that follows a warning', function()
      local items = parse({
        'LaTeX Warning: Reference undefined.',
        '! Undefined control sequence.',
        'l.9 \\oops',
      })
      T.eq(2, #items)
      T.eq('W', items[1].type)
      T.eq('E', items[2].type)
      T.eq(9, items[2].lnum)
    end)

    it('classifies package and class infos as info', function()
      local items = parse({
        'Package hyperref Info: Option `colorlinks\' set `true\'.',
        'Class scrbook Info: Some detail.',
      })
      T.eq(2, #items)
      T.eq('I', items[1].type)
      T.eq('I', items[2].type)
    end)

    it('classifies font warnings as info', function()
      local items = parse({ 'LaTeX Font Warning: Font shape `OT1/cmr/bx/sc\' undefined' })
      T.eq('I', items[1].type)
    end)

    it('keeps a package warning at warning level', function()
      local items = parse({ 'Package geometry Warning: Over-specification in h-setup.' })
      T.eq('W', items[1].type)
    end)

    it('attributes a message to the file on top of the ( ) stack', function()
      local items, root = parse({
        '(./chapters/intro.tex',
        'LaTeX Warning: Reference undefined on input line 3.',
        ')',
        'LaTeX Warning: Another one on input line 4.',
      })
      T.eq(2, #items)
      T.eq(root .. '/chapters/intro.tex', items[1].filename)
      T.eq(root .. '/main.tex', items[2].filename)
    end)

    it('ignores a parenthesis that is not a file name', function()
      local items, root = parse({
        '(see the manual)',
        'LaTeX Warning: Reference undefined on input line 3.',
      })
      T.eq(root .. '/main.tex', items[1].filename)
    end)

    describe('boxes', function()
      local log = {
        'Overfull \\hbox (12.0pt too wide) in paragraph at lines 4--5',
        'Underfull \\vbox (badness 10000) has occurred while \\output is active',
        'LaTeX Warning: Reference undefined on input line 9.',
      }

      it('drops them by default', function()
        local items = parse(log)
        T.eq(1, #items)
        T.eq('W', items[1].type)
        T.matches('Reference undefined', items[1].text)
      end)

      it('collects them when qf.boxes is set', function()
        config.setup({ qf = { boxes = true } })
        local items = parse(log)
        T.eq(3, #items)
        T.eq(4, items[1].lnum)
        T.matches('^Overfull', items[1].text)
        T.eq(0, items[2].lnum)
      end)
    end)

    describe('filtering', function()
      it('drops the built-in noise', function()
        local items = parse({
          'Package hyperref Warning: Token not allowed in a PDF string (Unicode):',
        })
        T.eq(0, #items)
      end)

      it('applies the user patterns', function()
        config.setup({ qf = { ignore_filters = { 'Reference `sec:' } } })
        local items = parse({
          'LaTeX Warning: Reference `sec:intro\' undefined on input line 3.',
          'LaTeX Warning: Reference `fig:one\' undefined on input line 4.',
        })
        T.eq(1, #items)
        T.matches('fig:one', items[1].text)
      end)
    end)

    it('returns nothing for a log that does not exist', function()
      T.eq({}, qf.parse_log('/nonexistent/nvim-tex/main.log', '/tmp', '/tmp/main.tex'))
    end)
  end)

  describe('parse_blg', function()
    it('picks up biber warnings and their line numbers', function()
      local blg = H.write(H.tmpdir() .. '/main.blg', {
        'Warning--I didn\'t find a database entry for "knuth1984"',
        'Warning--empty journal in smith2020 line 12 in refs.bib',
        'Database file #1: refs.bib',
      })
      local items = qf.parse_blg(blg, '/tmp/main.tex')
      T.eq(2, #items)
      T.eq('W', items[1].type)
      T.eq('/tmp/main.tex', items[1].filename)
      T.eq(12, items[2].lnum)
      T.eq('refs.bib', items[2].filename)
    end)
  end)

  describe('level', function()
    it('defaults to warning', function()
      T.eq('warning', qf.level())
    end)

    it('follows the configuration', function()
      config.setup({ qf = { level = 'error' } })
      -- `set_level` in H.reset installs an override, so clear it first.
      qf.set_level('error')
      T.eq('error', qf.level())
    end)

    it('cycles error -> warning -> info -> error', function()
      qf.set_level('error')
      T.eq('warning', qf.cycle_level())
      T.eq('info', qf.cycle_level())
      T.eq('error', qf.cycle_level())
    end)

    it('rejects an unknown level and says so', function()
      qf.set_level('warning')
      qf.set_level('nonsense')
      T.eq('warning', qf.level())
      T.ok(H.notified('unknown qf%.level'))
    end)

    it('lists the known levels', function()
      T.eq({ 'error', 'warning', 'info' }, qf.levels())
    end)
  end)

  describe('update', function()
    --- A project whose log is `lines`.
    ---@param lines string[]
    ---@return table
    local function project_with_log(lines)
      local root = H.tmpdir()
      H.write(root .. '/main.log', lines)
      return H.project(root .. '/main.tex')
    end

    it('counts every severity, including the hidden ones', function()
      local project = project_with_log({
        './main.tex:1: Boom.',
        'LaTeX Warning: Reference undefined on input line 3.',
        'Package hyperref Info: Just so you know.',
      })
      local errors, warnings, infos = qf.update(project, { silent = true })
      T.eq(1, errors)
      T.eq(1, warnings)
      T.eq(1, infos)
    end)

    it('only puts what the level shows into the quickfix list', function()
      local project = project_with_log({
        './main.tex:1: Boom.',
        'LaTeX Warning: Reference undefined on input line 3.',
        'Package hyperref Info: Just so you know.',
      })
      qf.update(project, { silent = true })
      T.eq(2, #vim.fn.getqflist())
      T.eq(1, project.qf_hidden)

      qf.set_level('error')
      qf.update(project, { silent = true })
      T.eq(1, #vim.fn.getqflist())
      T.eq(2, project.qf_hidden)

      qf.set_level('info')
      qf.update(project, { silent = true })
      T.eq(3, #vim.fn.getqflist())
      T.eq(0, project.qf_hidden)
    end)

    it('sorts errors first but keeps the log order within a severity', function()
      local project = project_with_log({
        'LaTeX Warning: first warning on input line 1.',
        './main.tex:2: first error.',
        'LaTeX Warning: second warning on input line 3.',
        './main.tex:4: second error.',
      })
      qf.update(project, { silent = true })
      local texts = vim.tbl_map(function(item)
        return item.text
      end, vim.fn.getqflist())
      T.eq(4, #texts)
      T.matches('first error', texts[1])
      T.matches('second error', texts[2])
      T.matches('first warning', texts[3])
      T.matches('second warning', texts[4])
    end)

    it('mentions the level and the hidden count in the title', function()
      local project = project_with_log({
        './main.tex:1: Boom.',
        'Package hyperref Info: Just so you know.',
      })
      qf.update(project, { silent = true })
      T.matches('%[warning%]', vim.fn.getqflist({ title = true }).title)
      T.matches('1 hidden', vim.fn.getqflist({ title = true }).title)
    end)

    it('does nothing when the quickfix integration is off', function()
      config.setup({ qf = { enabled = false } })
      local project = project_with_log({ './main.tex:1: Boom.' })
      T.eq(0, ({ qf.update(project, { silent = true }) })[1])
      T.eq(0, #vim.fn.getqflist())
    end)
  end)
end)
