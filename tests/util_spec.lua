local H = require('tests.helpers')
local util = require('nvim-tex.util')

describe('util', function()
  after_each(H.cleanup)

  describe('normalize', function()
    it('strips a trailing slash', function()
      T.eq('/tmp/foo', util.normalize('/tmp/foo/'))
      T.eq('/tmp/foo', util.normalize('/tmp/foo///'))
    end)

    it('resolves . and ..', function()
      T.eq('/tmp/foo', util.normalize('/tmp/bar/../foo/.'))
    end)

    it('expands ~', function()
      T.eq(vim.fs.normalize(vim.env.HOME) .. '/x.tex', util.normalize('~/x.tex'))
    end)

    it('makes a relative path absolute', function()
      T.matches('^/', util.normalize('x.tex'))
    end)
  end)

  describe('join', function()
    it('collapses repeated separators', function()
      T.eq('/a/b/c.tex', util.join('/a/', '/b', 'c.tex'))
    end)

    it('keeps a single separator between the parts', function()
      T.eq('/a/b', util.join('/a', 'b'))
    end)
  end)

  describe('is_file and is_dir', function()
    it('tell the two apart', function()
      local dir = H.tmpdir()
      local file = H.write(dir .. '/a.tex', 'x')
      T.ok(util.is_file(file))
      T.falsy(util.is_dir(file))
      T.ok(util.is_dir(dir))
      T.falsy(util.is_file(dir))
    end)

    it('report false for what does not exist', function()
      T.falsy(util.is_file('/nonexistent/nvim-tex/a.tex'))
      T.falsy(util.is_dir('/nonexistent/nvim-tex'))
    end)
  end)

  describe('readlines', function()
    it('drops the trailing empty line', function()
      local file = H.write(H.tmpdir() .. '/a.txt', { 'one', 'two' })
      T.eq({ 'one', 'two' }, util.readlines(file))
    end)

    it('honours the line limit', function()
      local file = H.write(H.tmpdir() .. '/a.txt', { 'one', 'two', 'three' })
      T.eq({ 'one', 'two' }, util.readlines(file, 2))
    end)

    it('returns an empty list for an unreadable file', function()
      T.eq({}, util.readlines('/nonexistent/nvim-tex/a.txt'))
    end)
  end)

  describe('writelines', function()
    it('round-trips through readlines and creates the directory', function()
      local path = H.tmpdir() .. '/deep/nested/a.txt'
      util.writelines(path, { 'one', 'two' })
      T.eq({ 'one', 'two' }, util.readlines(path))
    end)
  end)

  describe('as_cmd', function()
    it('wraps a string', function()
      T.eq({ 'latexmk' }, util.as_cmd('latexmk'))
    end)

    it('copies a list instead of aliasing it', function()
      local original = { 'nix', 'run', 'latexmk' }
      local copy = util.as_cmd(original)
      T.eq(original, copy)
      copy[#copy + 1] = 'extra'
      T.eq(3, #original)
    end)
  end)

  describe('escape_replacement', function()
    it('doubles percent signs so gsub takes them literally', function()
      T.eq('100%%', util.escape_replacement('100%'))
      T.eq('a/b', util.escape_replacement('a/b'))
    end)
  end)

  describe('expand_args', function()
    it('substitutes the placeholders', function()
      T.eq(
        { '--file', '/tmp/a.pdf', '--line', '12' },
        util.expand_args({ '--file', '@pdf', '--line', '@line' }, { pdf = '/tmp/a.pdf', line = 12 })
      )
    end)

    it('leaves unknown placeholders alone', function()
      T.eq({ '@nope' }, util.expand_args({ '@nope' }, { pdf = 'x' }))
    end)

    it('survives a replacement containing a percent sign', function()
      T.eq({ '/tmp/100%/a.pdf' }, util.expand_args({ '@pdf' }, { pdf = '/tmp/100%/a.pdf' }))
    end)
  end)

  describe('resolve', function()
    it('passes a plain value through', function()
      T.eq('build', util.resolve('build', {}))
    end)

    it('calls a function with the file info', function()
      local seen
      local value = util.resolve(function(info)
        seen = info
        return info.target_name .. '-out'
      end, { target_name = 'thesis' })
      T.eq('thesis-out', value)
      T.eq({ target_name = 'thesis' }, seen)
    end)
  end)

  describe('scratch', function()
    it('creates a read-only nofile buffer with the given lines', function()
      local bufnr = util.scratch('nvim-tex://test-scratch', { 'one', 'two' })
      T.eq({ 'one', 'two' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
      T.eq('nofile', vim.bo[bufnr].buftype)
      T.falsy(vim.bo[bufnr].modifiable)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('reuses the buffer of the same name', function()
      local first = util.scratch('nvim-tex://test-scratch', { 'one' })
      local second = util.scratch('nvim-tex://test-scratch', { 'two' })
      T.eq(first, second)
      T.eq({ 'two' }, vim.api.nvim_buf_get_lines(second, 0, -1, false))
      vim.api.nvim_buf_delete(second, { force = true })
    end)
  end)
end)
