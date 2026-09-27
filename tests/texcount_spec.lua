local H = require('tests.helpers')
local config = require('nvim-tex.config')
local texcount = require('nvim-tex.texcount')

--- Run `fn` and wait for the notification it eventually sends.
---@param fn function
---@return table|nil
local function reported(fn)
  local before = #H.notifications
  fn()
  vim.wait(10000, function()
    return #H.notifications > before
  end, 20)
  return H.notifications[before + 1]
end

describe('texcount', function()
  local project

  before_each(function()
    project = H.project(H.tmpdir() .. '/thesis.tex')
  end)

  after_each(H.cleanup)

  describe('build_cmd', function()
    it('asks for a brief, merged sum of the main file', function()
      T.eq({ 'texcount', '-nosub', '-sum', '-merge', '-q', '-1', project.main }, texcount.build_cmd(project, {}))
    end)

    it('counts letters with -letter', function()
      T.contains(texcount.build_cmd(project, { letters = true }), '-letter')
    end)

    it('gives the per-file report for a detailed count', function()
      local cmd = texcount.build_cmd(project, { detailed = true })
      T.contains(cmd, '-inc')
      T.excludes(cmd, '-1')
    end)

    it('reads a range from stdin, resolving includes against the root', function()
      local cmd = texcount.build_cmd(project, { stdin = true, detailed = true })
      T.eq('-', cmd[#cmd])
      T.contains(cmd, '-dir=' .. project.root)
      T.contains(cmd, '-merge')
    end)

    it('appends the configured options', function()
      config.setup({ texcount = { options = { '-incbib' } } })
      local cmd = texcount.build_cmd(project, {})
      T.eq('-incbib', cmd[#cmd - 1])
    end)
  end)

  it('finds the number and the errors in the output', function()
    T.eq(42, texcount.parse_brief({ '42' }))
    T.eq(nil, texcount.parse_brief({ 'File: x.tex' }))
    T.eq(
      { 'File not found or not readable: x.tex' },
      texcount.errors(
        { '0', ' (errors:1)' },
        { 'Possible precedence problem', 'ERROR: File not found or not readable: x.tex' }
      )
    )
    T.eq({ '(errors:1)' }, texcount.errors({ '0', ' (errors:1)' }, {}))
    T.eq({}, texcount.errors({ '42' }, { 'Possible precedence problem' }))
  end)

  describe('with texcount installed', function()
    before_each(function()
      if vim.fn.executable('texcount') == 0 then
        T.skip('texcount is not installed')
      end
      H.write(project.root .. '/ch/one.tex', 'Chapter text.')
      H.write(project.main, {
        '\\documentclass{article}',
        '\\begin{document}',
        'Hello world, this is text.',
        '\\input{ch/one}',
        '\\end{document}',
      })
    end)

    it('counts the document with its includes', function()
      local n = reported(function()
        texcount.count(project)
      end)
      T.eq('thesis.tex: 7 words', n.message:gsub('^%[nvim%-tex%] ', ''))
    end)

    it('counts a range', function()
      local n = reported(function()
        texcount.count(project, { lines = { 'two words', '\\input{ch/one}' } })
      end)
      T.matches('selection: 4 words', n.message)
    end)

    it('counts letters', function()
      local n = reported(function()
        texcount.count(project, { letters = true, lines = { 'Größe über' } })
      end)
      T.matches('selection: 9 letters', n.message)
    end)

    it('reports a missing main file as an error', function()
      vim.fn.delete(project.main)
      local n = reported(function()
        texcount.count(project)
      end)
      T.eq(vim.log.levels.ERROR, n.level)
      T.matches('texcount failed: File not found', n.message)
    end)

    it('shows the detailed report in a scratch buffer', function()
      texcount.count(project, { detailed = true })
      vim.wait(10000, function()
        return vim.fn.bufnr('nvim-tex://texcount') > 0
      end, 20)
      local lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr('nvim-tex://texcount'), 0, -1, false)
      T.ok(vim.iter(lines):any(function(line)
        return line:match('^Included file:') ~= nil
      end))
    end)
  end)
end)
