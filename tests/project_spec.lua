local H = require('tests.helpers')
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')

describe('project', function()
  after_each(H.cleanup)

  describe('detect_main', function()
    it('honours b:tex_main above everything else', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ '\\documentclass{article}', '\\begin{document}' }, { name = dir .. '/chapter.tex' })
      vim.api.nvim_buf_set_var(bufnr, 'tex_main', dir .. '/elsewhere.tex')
      T.eq(dir .. '/elsewhere.tex', project_mod.detect_main(bufnr))
    end)

    it('honours the main_file option', function()
      local dir = H.tmpdir()
      config.setup({ main_file = dir .. '/thesis.tex' })
      local bufnr = H.buf({ 'text' }, { name = dir .. '/chapter.tex' })
      T.eq(dir .. '/thesis.tex', project_mod.detect_main(bufnr))
    end)

    it('calls main_file when it is a function', function()
      local dir = H.tmpdir()
      config.setup({
        main_file = function(bufnr)
          return vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)) .. '/computed.tex'
        end,
      })
      local bufnr = H.buf({ 'text' }, { name = dir .. '/chapter.tex' })
      T.eq(dir .. '/computed.tex', project_mod.detect_main(bufnr))
    end)

    it('follows a % !TEX root directive', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ '% !TEX root = ../main.tex', 'text' }, {
        name = dir .. '/chapters/intro.tex',
      })
      T.eq(dir .. '/main.tex', project_mod.detect_main(bufnr))
    end)

    it('adds the .tex extension the directive left out', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ '% !TEX root = main' }, { name = dir .. '/intro.tex' })
      T.eq(dir .. '/main.tex', project_mod.detect_main(bufnr))
    end)

    it('reads a directive from the last lines too', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ 'a', 'b', 'c', 'd', 'e', 'f', 'g', '% !TEX root = main.tex' }, {
        name = dir .. '/intro.tex',
      })
      T.eq(dir .. '/main.tex', project_mod.detect_main(bufnr))
    end)

    it('treats a buffer with \\documentclass as its own main file', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ '\\documentclass{article}', '\\begin{document}' }, {
        name = dir .. '/standalone.tex',
      })
      T.eq(dir .. '/standalone.tex', project_mod.detect_main(bufnr))
    end)

    it('searches upwards for a root that includes this file', function()
      local dir = H.tmpdir()
      H.write(dir .. '/main.tex', {
        '\\documentclass{book}',
        '\\begin{document}',
        '\\input{chapters/intro}',
        '\\end{document}',
      })
      local bufnr = H.buf({ 'Some prose.' }, { name = dir .. '/chapters/intro.tex' })
      T.eq(dir .. '/main.tex', project_mod.detect_main(bufnr))
    end)

    it('prefers the root that references the file over any other root', function()
      local dir = H.tmpdir()
      H.write(dir .. '/other.tex', { '\\documentclass{article}', '\\begin{document}' })
      H.write(dir .. '/real.tex', {
        '\\documentclass{book}',
        '\\begin{document}',
        '\\include{intro}',
      })
      local bufnr = H.buf({ 'Some prose.' }, { name = dir .. '/intro.tex' })
      T.eq(dir .. '/real.tex', project_mod.detect_main(bufnr))
    end)

    it('does not take a shared preamble for a root', function()
      local dir = H.tmpdir()
      H.write(dir .. '/sheet.tex', {
        '\\input{header}',
        '\\begin{document}',
        '\\end{document}',
      })
      local bufnr = H.buf({ '\\documentclass{article}', '\\usepackage{amsmath}' }, {
        name = dir .. '/header.tex',
      })
      T.eq(dir .. '/sheet.tex', project_mod.detect_main(bufnr))
    end)

    it('prefers the open project that includes the file', function()
      local dir = H.tmpdir()
      H.write(dir .. '/header.tex', { '\\documentclass{article}' })
      H.write(dir .. '/sheet.tex', { '\\input{header}', '\\begin{document}' })
      local exam = { '\\input{header}', '\\begin{document}' }
      H.write(dir .. '/exam.tex', exam)
      project_mod.get(H.buf(exam, { name = dir .. '/exam.tex' }))
      local bufnr = H.buf({ '\\documentclass{article}' }, { name = dir .. '/header.tex' })
      T.eq(dir .. '/exam.tex', project_mod.detect_main(bufnr))
    end)

    it('falls back to the buffer itself when no root is anywhere', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ 'Some prose.' }, { name = dir .. '/lonely.tex' })
      T.eq(dir .. '/lonely.tex', project_mod.detect_main(bufnr))
    end)
  end)

  describe('get', function()
    it('derives root, name and directories from the main file', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ '\\documentclass{article}', '\\begin{document}' }, { name = dir .. '/thesis.tex' })
      local project = project_mod.get(bufnr)
      T.eq(dir .. '/thesis.tex', project.main)
      T.eq(dir, project.root)
      T.eq('thesis', project.name)
      T.eq(dir, project.out_dir)
      T.falsy(project.out_dir_set)
    end)

    it('resolves a relative out_dir against the main file', function()
      local dir = H.tmpdir()
      config.setup({ compiler = { latexmk = { out_dir = 'build' } } })
      local bufnr = H.buf({ '\\documentclass{article}', '\\begin{document}' }, { name = dir .. '/thesis.tex' })
      local project = project_mod.get(bufnr)
      T.eq(dir .. '/build', project.out_dir)
      T.ok(project.out_dir_set)
    end)

    it('looks for the log in out_dir when no aux_dir is set, as latexmk writes it', function()
      local dir = H.tmpdir()
      config.setup({ compiler = { latexmk = { out_dir = 'build' } } })
      local bufnr = H.buf({ '\\documentclass{article}', '\\begin{document}' }, { name = dir .. '/thesis.tex' })
      local project = project_mod.get(bufnr)
      T.eq(dir .. '/build', project.aux_dir)
      T.falsy(project.aux_dir_set)
      T.eq(dir .. '/build/thesis.log', project_mod.log_file(project))
    end)

    it('keeps a separate aux_dir', function()
      local dir = H.tmpdir()
      config.setup({ compiler = { latexmk = { out_dir = 'build', aux_dir = 'aux' } } })
      local bufnr = H.buf({ '\\documentclass{article}', '\\begin{document}' }, { name = dir .. '/thesis.tex' })
      local project = project_mod.get(bufnr)
      T.eq(dir .. '/aux', project.aux_dir)
      T.ok(project.aux_dir_set)
    end)

    it('picks up the % !TeX program directive', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ '% !TeX program = lualatex', '\\documentclass{article}', '\\begin{document}' }, {
        name = dir .. '/thesis.tex',
      })
      T.eq('lualatex', project_mod.get(bufnr).tex_program)
    end)

    it('shares one project between the buffers of one document', function()
      local dir = H.tmpdir()
      H.write(dir .. '/main.tex', {
        '\\documentclass{book}',
        '\\begin{document}',
        '\\input{intro}',
        '\\input{outro}',
      })
      local one = H.buf({ 'a' }, { name = dir .. '/intro.tex' })
      local two = H.buf({ 'b' }, { name = dir .. '/outro.tex' })
      T.eq(project_mod.get(one), project_mod.get(two))
      T.eq(2, #project_mod.buffers(project_mod.get(one)))
    end)

    it('redetects after invalidate', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ '\\documentclass{article}', '\\begin{document}' }, { name = dir .. '/a.tex' })
      T.eq(dir .. '/a.tex', project_mod.get(bufnr).main)

      vim.api.nvim_buf_set_var(bufnr, 'tex_main', dir .. '/b.tex')
      T.eq(dir .. '/a.tex', project_mod.get(bufnr).main, 'still cached')
      project_mod.invalidate(bufnr)
      T.eq(dir .. '/b.tex', project_mod.get(bufnr).main)
    end)

    it('forgets a project entirely', function()
      local dir = H.tmpdir()
      local bufnr = H.buf({ '\\documentclass{article}', '\\begin{document}' }, { name = dir .. '/a.tex' })
      local project = project_mod.get(bufnr)
      project_mod.forget(project)
      T.eq(nil, project_mod.projects[project.main])
      T.eq(0, #project_mod.buffers(project))
    end)
  end)

  describe('paths', function()
    it('puts the output next to the aux files by default', function()
      local project = H.project('/docs/thesis.tex')
      T.eq('/docs/thesis.pdf', project_mod.output_file(project))
      T.eq('/docs/thesis.dvi', project_mod.output_file(project, 'dvi'))
      T.eq('/docs/thesis.log', project_mod.log_file(project))
    end)

    it('takes the log from the aux directory', function()
      local project = H.project('/docs/thesis.tex', { aux_dir = '/docs/build' })
      T.eq('/docs/build/thesis.log', project_mod.log_file(project))
    end)
  end)
end)
