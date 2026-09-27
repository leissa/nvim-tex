local H = require('tests.helpers')
local config = require('nvim-tex.config')
local compiler = require('nvim-tex.compiler')
local project_mod = require('nvim-tex.project')
local tectonic = require('nvim-tex.compiler.tectonic')
local util = require('nvim-tex.util')

describe('compiler.tectonic', function()
  local project

  before_each(function()
    config.setup({ compiler = { method = 'tectonic' } })
    project = H.project(H.tmpdir() .. '/thesis.tex')
  end)

  after_each(H.cleanup)

  describe('build_cmd', function()
    it('puts the options and the target together', function()
      T.eq({ 'tectonic', '--synctex', '--keep-logs', project.main }, tectonic.build_cmd(project))
    end)

    it('keeps the user option list verbatim', function()
      config.setup({ compiler = { method = 'tectonic', tectonic = { options = { '--keep-logs' } } } })
      T.eq({ 'tectonic', '--keep-logs', project.main }, tectonic.build_cmd(project))
    end)

    it('passes --outdir only when an output directory was configured, and creates it', function()
      T.excludes(tectonic.build_cmd(project), '--outdir')

      project.out_dir = project.root .. '/build'
      project.out_dir_set = true
      local cmd = tectonic.build_cmd(project)
      T.contains(cmd, '--outdir')
      T.contains(cmd, project.root .. '/build')
      T.ok(util.is_dir(project.root .. '/build'))
    end)

    it('adds the project root to the search path for a target elsewhere', function()
      T.excludes(tectonic.build_cmd(project), '-Z')
      local cmd = tectonic.build_cmd(project, { target = '/tmp/snippet.tex' })
      T.contains(cmd, 'search-path=' .. project.root)
      T.eq('/tmp/snippet.tex', cmd[#cmd])
    end)
  end)

  describe('clean_files', function()
    it('lists the leftovers that exist, and the PDF only for a full clean', function()
      H.write(project.root .. '/thesis.log', '')
      H.write(project.root .. '/thesis.synctex.gz', '')
      H.write(project.root .. '/thesis.pdf', '')
      H.write(project.root .. '/other.log', '')

      local files = tectonic.clean_files(project, false)
      T.eq(2, #files)
      T.contains(files, project.root .. '/thesis.log')
      T.contains(files, project.root .. '/thesis.synctex.gz')

      T.contains(tectonic.clean_files(project, true), project.root .. '/thesis.pdf')
    end)

    it('honours clean_ext', function()
      config.setup({ compiler = { method = 'tectonic', tectonic = { clean_ext = 'xdv' } } })
      H.write(project.root .. '/thesis.xdv', '')
      T.eq({ project.root .. '/thesis.xdv' }, tectonic.clean_files(project, false))
    end)
  end)

  it('recognises a failure line', function()
    T.ok(tectonic.is_failure_line('error: thesis.tex:3: Undefined control sequence'))
    T.falsy(tectonic.is_failure_line('note: Running TeX ...'))
  end)

  describe('through nvim-tex.compiler', function()
    it(':TexClean removes the files itself', function()
      H.write(project.root .. '/thesis.log', '')
      H.write(project.root .. '/thesis.pdf', '')
      compiler.clean(project, false)
      T.falsy(util.is_file(project.root .. '/thesis.log'))
      T.ok(util.is_file(project.root .. '/thesis.pdf'))
      T.ok(H.notified('cleaned auxiliary files'))
    end)

    it('always runs single shot, whatever the caller asks for', function()
      -- `sh -c true` ignores the arguments appended to it and exits at once.
      config.setup({
        compiler = { method = 'tectonic', silent = true, tectonic = { executable = { 'sh', '-c', 'true' } } },
      })
      compiler.start(project, { continuous = true })
      T.falsy(project.compiler.continuous)
      vim.wait(2000, function()
        return not compiler.is_running(project)
      end)
      T.eq('success', project.last_status)
    end)
  end)

  it('puts the log next to the PDF', function()
    local dir = H.tmpdir()
    config.setup({ compiler = { method = 'tectonic', tectonic = { out_dir = 'build' } } })
    local bufnr = H.buf({ '\\documentclass{article}' }, { name = dir .. '/thesis.tex' })
    local p = project_mod.get(bufnr)
    T.eq(dir .. '/build', p.out_dir)
    T.eq(dir .. '/build/thesis.log', project_mod.log_file(p))
  end)
end)
