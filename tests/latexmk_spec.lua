local H = require('tests.helpers')
local config = require('nvim-tex.config')
local latexmk = require('nvim-tex.compiler.latexmk')

--- Index of `value` in `cmd`, or nil.
---@param cmd string[]
---@param value string
---@return integer|nil
local function index_of(cmd, value)
  for i, item in ipairs(cmd) do
    if item == value then
      return i
    end
  end
  return nil
end

describe('compiler.latexmk', function()
  local project

  before_each(function()
    project = H.project(H.tmpdir() .. '/thesis.tex')
  end)

  after_each(H.cleanup)

  describe('build_cmd', function()
    it('puts the engine flag, the options and the target together', function()
      config.setup({ compiler = { latexmk = { continuous = false } } })
      local cmd = latexmk.build_cmd(project)
      T.eq('latexmk', cmd[1])
      T.eq('-pdf', cmd[2])
      T.contains(cmd, '-synctex=1')
      T.contains(cmd, '-interaction=nonstopmode')
      T.eq(project.main, cmd[#cmd])
    end)

    it('honours a string executable and a wrapper list alike', function()
      config.setup({
        compiler = { latexmk = { executable = { 'nix', 'run', 'latexmk' }, continuous = false } },
      })
      local cmd = latexmk.build_cmd(project)
      T.eq({ 'nix', 'run', 'latexmk' }, { cmd[1], cmd[2], cmd[3] })
    end)

    it('maps the TeX program directive onto the engine flag', function()
      config.setup({ compiler = { latexmk = { continuous = false } } })
      project.tex_program = 'LuaLaTeX'
      T.contains(latexmk.build_cmd(project), '-lualatex')
      T.excludes(latexmk.build_cmd(project), '-pdf')
    end)

    it('splits a multi-word engine flag', function()
      config.setup({ compiler = { latexmk = { continuous = false } } })
      project.tex_program = 'context (luatex)'
      local cmd = latexmk.build_cmd(project)
      T.contains(cmd, '-pdf')
      T.contains(cmd, '-pdflatex=context')
    end)

    it('adds -pvc -view=none in continuous mode', function()
      config.setup({ compiler = { latexmk = { continuous = true } } })
      local cmd = latexmk.build_cmd(project)
      T.contains(cmd, '-pvc')
      T.contains(cmd, '-view=none')
    end)

    it('lets the caller override the continuous setting', function()
      config.setup({ compiler = { latexmk = { continuous = true } } })
      T.excludes(latexmk.build_cmd(project, { continuous = false }), '-pvc')

      config.setup({ compiler = { latexmk = { continuous = false } } })
      T.contains(latexmk.build_cmd(project, { continuous = true }), '-pvc')
    end)

    it('compiles the given target instead of the main file', function()
      local cmd = latexmk.build_cmd(project, { target = '/tmp/snippet.tex' })
      T.eq('/tmp/snippet.tex', cmd[#cmd])
    end)

    it('passes -outdir only when an output directory was configured', function()
      config.setup({ compiler = { latexmk = { continuous = false } } })
      T.eq(nil, index_of(latexmk.build_cmd(project), '-outdir=' .. project.out_dir))

      project.out_dir = project.root .. '/build'
      project.out_dir_set = true
      T.contains(latexmk.build_cmd(project), '-outdir=' .. project.root .. '/build')
    end)

    it('pairs -auxdir with -emulate-aux-dir', function()
      config.setup({ compiler = { latexmk = { continuous = false } } })
      project.aux_dir = project.root .. '/aux'
      project.aux_dir_set = true
      local cmd = latexmk.build_cmd(project)
      T.contains(cmd, '-auxdir=' .. project.root .. '/aux')
      T.contains(cmd, '-emulate-aux-dir')
    end)

    it('creates the directories it passes on', function()
      project.out_dir = project.root .. '/build'
      project.out_dir_set = true
      latexmk.build_cmd(project)
      T.ok(require('nvim-tex.util').is_dir(project.root .. '/build'))
    end)

    it('keeps the user option list verbatim', function()
      config.setup({ compiler = { latexmk = { continuous = false, options = { '-quiet' } } } })
      local cmd = latexmk.build_cmd(project)
      T.eq({ 'latexmk', '-pdf', '-quiet', project.main }, cmd)
    end)
  end)

  describe('clean_cmd', function()
    it('uses -c by default and -C for a full clean', function()
      T.eq({ 'latexmk', '-c', project.main }, latexmk.clean_cmd(project, false))
      T.eq({ 'latexmk', '-C', project.main }, latexmk.clean_cmd(project, true))
    end)

    it('passes the extra extensions through -e', function()
      config.setup({ compiler = { latexmk = { clean_ext = 'bbl run.xml' } } })
      local cmd = latexmk.clean_cmd(project, false)
      T.eq('-e', cmd[2])
      T.eq("$clean_ext = 'bbl run.xml'", cmd[3])
    end)

    it('repeats the directory flags so latexmk cleans the right place', function()
      project.out_dir = project.root .. '/build'
      project.out_dir_set = true
      T.contains(latexmk.clean_cmd(project, false), '-outdir=' .. project.root .. '/build')
    end)
  end)

  describe('output line recognition', function()
    it('spots the end of a continuous cycle', function()
      T.ok(latexmk.is_finished_line('=== Watching for updated files. Use ctrl/C to stop ...'))
      T.falsy(latexmk.is_finished_line('Latexmk: Run number 1 of rule \'pdflatex\''))
    end)

    it('spots the start of a run', function()
      T.ok(latexmk.is_started_line("Latexmk: Run number 1 of rule 'pdflatex'"))
      T.ok(latexmk.is_started_line('Latexmk: applying rule \'pdflatex\'...'))
      T.falsy(latexmk.is_started_line('This is pdfTeX, Version 3.141592653'))
    end)

    it('spots a failure', function()
      T.ok(latexmk.is_failure_line('Latexmk: Errors, so I did not finish making targets'))
      T.ok(latexmk.is_failure_line('Latexmk: Failure in processing file'))
      T.ok(latexmk.is_failure_line('Latexmk: Did not finish processing file'))
      T.falsy(latexmk.is_failure_line('Latexmk: All targets are up-to-date'))
    end)
  end)
end)
