local H = require('tests.helpers')
local config = require('nvim-tex.config')
local viewer = require('nvim-tex.viewer')

--- The context `nvim-tex.viewer` hands to a backend. An override of `vim.NIL`
--- removes the field, which a plain `nil` cannot do.
---@param overrides table|nil
---@return table
local function ctx(overrides)
  local base = {
    pdf = '/docs/thesis.pdf',
    tex = '/docs/thesis.tex',
    line = 42,
    col = 7,
    server = '/tmp/nvim.sock',
  }
  for key, value in pairs(overrides or {}) do
    base[key] = value ~= vim.NIL and value or nil
  end
  return base
end

--- The argument following `flag` in `cmd`.
---@param cmd string[]
---@param flag string
---@return string|nil
local function value_after(cmd, flag)
  for i, item in ipairs(cmd) do
    if item == flag then
      return cmd[i + 1]
    end
  end
  return nil
end

describe('viewer', function()
  local project

  before_each(function()
    project = H.project('/docs/thesis.tex')
  end)

  after_each(H.cleanup)

  describe('backend selection', function()
    it('rejects an unknown method', function()
      config.setup({ view = { method = 'acroread' } })
      T.eq(nil, viewer.backend())
      T.ok(H.notified('unknown view method'))
    end)

    it('rejects a method whose executable is missing', function()
      config.setup({ view = { method = 'zathura', zathura = { executable = 'nvim-tex-no-such-viewer' } } })
      T.eq(nil, viewer.backend())
      T.ok(H.notified('is not executable'))
    end)

    it('returns the named backend when it is there', function()
      config.setup({ view = { method = 'general', general = { executable = 'sh' } } })
      local backend = viewer.backend()
      T.ok(backend)
      T.eq('general', backend.name)
    end)

    it("falls back through the list for 'auto'", function()
      -- Nothing but `general` can be found, so `auto` has to land there.
      config.setup({
        view = {
          method = 'auto',
          zathura = { executable = 'nvim-tex-no-such-viewer' },
          sioyek = { executable = 'nvim-tex-no-such-viewer' },
          skim = { executable = 'nvim-tex-no-such-viewer' },
          okular = { executable = 'nvim-tex-no-such-viewer' },
          general = { executable = 'sh' },
        },
      })
      local backend = viewer.backend()
      T.ok(backend)
      T.eq('general', backend.name)
    end)
  end)

  describe('zathura', function()
    local zathura = require('nvim-tex.viewer.zathura')

    it('asks for a forward search when a line is known', function()
      local cmd = zathura.spawn_cmd(project, ctx())
      T.eq('zathura', cmd[1])
      T.contains(cmd, '--synctex-forward')
      T.contains(cmd, '42:7:/docs/thesis.tex')
      T.eq('/docs/thesis.pdf', cmd[#cmd])
    end)

    it('just opens the PDF without a line', function()
      local cmd = zathura.spawn_cmd(project, ctx({ line = vim.NIL, col = vim.NIL }))
      T.excludes(cmd, '--synctex-forward')
      T.eq('/docs/thesis.pdf', cmd[#cmd])
    end)

    it('wires up inverse search through -x when there is a server', function()
      local cmd = zathura.spawn_cmd(project, ctx())
      local editor = value_after(cmd, '-x')
      T.matches('NvimTexInverseSearch', editor)
      T.matches('/tmp/nvim%.sock', editor)
    end)

    it('leaves -x out without a server', function()
      T.excludes(zathura.spawn_cmd(project, ctx({ server = '' })), '-x')
    end)

    it('has no forward command without a running instance', function()
      T.eq(nil, zathura.forward_cmd(project, ctx()))
    end)

    it('talks to a running instance over D-Bus', function()
      if vim.fn.executable('dbus-send') == 0 then
        T.skip('dbus-send is not installed')
      end
      project.viewer = { pid = 4711 }
      local cmd = zathura.forward_cmd(project, ctx())
      T.eq('dbus-send', cmd[1])
      T.contains(cmd, '--dest=org.pwmt.zathura.PID-4711')
      T.contains(cmd, 'int32:42')
      T.contains(cmd, 'int32:7')
      T.contains(cmd, 'string:/docs/thesis.tex')
    end)

    it('stays quiet over D-Bus when use_dbus is off', function()
      config.setup({ view = { zathura = { use_dbus = false } } })
      project.viewer = { pid = 4711 }
      T.eq(nil, zathura.forward_cmd(project, ctx()))
    end)
  end)

  describe('sioyek', function()
    local sioyek = require('nvim-tex.viewer.sioyek')

    it('reuses its window and forwards the search', function()
      local cmd = sioyek.spawn_cmd(project, ctx())
      T.contains(cmd, '--reuse-window')
      T.contains(cmd, '--forward-search-file')
      T.contains(cmd, '/docs/thesis.tex')
      T.contains(cmd, '--forward-search-line')
      T.contains(cmd, '42')
    end)

    it('forward searches with the same command it launches with', function()
      T.eq(sioyek.spawn_cmd(project, ctx()), sioyek.forward_cmd(project, ctx()))
    end)
  end)

  describe('okular', function()
    local okular = require('nvim-tex.viewer.okular')

    it('encodes the source position in the URL', function()
      local cmd = okular.spawn_cmd(project, ctx())
      T.contains(cmd, '--unique')
      T.eq('/docs/thesis.pdf#src:42 /docs/thesis.tex', cmd[#cmd])
    end)

    it('opens the plain PDF without a line', function()
      T.eq('/docs/thesis.pdf', okular.spawn_cmd(project, ctx({ line = vim.NIL }))[3])
    end)
  end)

  describe('skim', function()
    local skim = require('nvim-tex.viewer.skim')

    it('passes line, PDF and source to displayline', function()
      local cmd = skim.spawn_cmd(project, ctx())
      T.eq({ '-r', '-g', '42', '/docs/thesis.pdf', '/docs/thesis.tex' },
        { cmd[2], cmd[3], cmd[4], cmd[5], cmd[6] })
    end)
  end)

  describe('general', function()
    local general = require('nvim-tex.viewer.general')

    it('opens the PDF with the default arguments', function()
      T.eq({ 'xdg-open', '/docs/thesis.pdf' }, general.spawn_cmd(project, ctx()))
    end)

    it('substitutes every placeholder', function()
      config.setup({
        view = {
          general = {
            executable = 'myviewer',
            args = { '--pdf', '@pdf', '--tex', '@tex', '--line', '@line', '--col', '@col', '--server', '@server' },
          },
        },
      })
      T.eq({
        'myviewer',
        '--pdf', '/docs/thesis.pdf',
        '--tex', '/docs/thesis.tex',
        '--line', '42',
        '--col', '7',
        '--server', '/tmp/nvim.sock',
      }, general.spawn_cmd(project, ctx()))
    end)

    it('cannot forward search', function()
      T.eq(nil, general.forward_cmd())
    end)
  end)

  describe('inverse search', function()
    it('opens the file and puts the cursor on the line', function()
      local dir = H.tmpdir()
      local file = H.write(dir .. '/thesis.tex', { 'one', 'two', 'three', 'four' })
      _G.NvimTexInverseSearch(3, file)
      vim.wait(500, function()
        return vim.api.nvim_buf_get_name(0) == file
      end)
      T.eq(file, vim.api.nvim_buf_get_name(0))
      T.eq(3, vim.api.nvim_win_get_cursor(0)[1])
      vim.cmd('silent! %bwipeout!')
    end)

    it('complains about a file that is not there', function()
      _G.NvimTexInverseSearch(3, '/nonexistent/nvim-tex/thesis.tex')
      vim.wait(500, function()
        return H.notified('inverse search')
      end)
      T.ok(H.notified('inverse search: no such file'))
    end)
  end)

  describe('is_running', function()
    it('is false without a viewer', function()
      T.falsy(viewer.is_running(project))
    end)

    it('is true while the handle is alive', function()
      project.viewer = { handle = { is_closing = function() return false end } }
      T.ok(viewer.is_running(project))
    end)
  end)
end)
