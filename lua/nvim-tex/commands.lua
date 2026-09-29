--- User commands. Every command acts on the project of the current buffer.
local cite = require('nvim-tex.cite')
local compiler = require('nvim-tex.compiler')
local imaps = require('nvim-tex.imaps')
local info = require('nvim-tex.info')
local project_mod = require('nvim-tex.project')
local qf = require('nvim-tex.qf')
local surround = require('nvim-tex.surround')
local texcount = require('nvim-tex.texcount')
local toc = require('nvim-tex.toc')
local viewer = require('nvim-tex.viewer')

local M = {}

---@return table
local function project()
  return project_mod.get(0)
end

--- `:TexCountWords` / `:TexCountLetters`.
---@param letters boolean
---@return function
local function count(letters)
  return function(opts)
    texcount.count(project(), {
      letters = letters,
      detailed = opts.bang,
      lines = opts.range > 0 and vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false) or nil,
    })
  end
end

--- All commands, as `{ name, fn, opts }`.
local COMMANDS = {
  {
    'TexCompile',
    function()
      compiler.compile(project())
    end,
    { desc = 'Start or stop compilation' },
  },
  {
    'TexCompileSS',
    function()
      compiler.compile_single_shot(project())
    end,
    { desc = 'Compile once' },
  },
  {
    'TexCompileSelected',
    function(opts)
      compiler.compile_selected(project(), opts.line1, opts.line2)
    end,
    { range = true, desc = 'Compile the selected lines as a standalone document' },
  },
  {
    'TexCompileOutput',
    function()
      compiler.show_output(project())
    end,
    { desc = 'Show the raw compiler output' },
  },
  {
    'TexStop',
    function()
      compiler.stop(project())
    end,
    { desc = 'Stop the compilation of this project' },
  },
  {
    'TexStopAll',
    function()
      compiler.stop_all()
    end,
    { desc = 'Stop all compilations' },
  },
  {
    'TexClean',
    function(opts)
      compiler.clean(project(), opts.bang)
    end,
    { bang = true, desc = 'Remove auxiliary files (! also removes the PDF)' },
  },
  {
    'TexView',
    function()
      viewer.view(project())
    end,
    { desc = 'Open the PDF viewer' },
  },
  {
    'TexForwardSearch',
    function()
      viewer.forward_search(project())
    end,
    { desc = 'Move the viewer to the cursor position' },
  },
  {
    'TexReverseSearch',
    function()
      viewer.reverse_search(project())
    end,
    { desc = 'Ask the viewer for its current position' },
  },
  {
    'TexErrors',
    function()
      qf.update(project(), { force_open = true, silent = false })
    end,
    { desc = 'Open the quickfix list with errors and warnings' },
  },
  {
    'TexQfLevel',
    function(opts)
      if opts.args ~= '' then
        qf.set_level(opts.args)
      else
        qf.cycle_level()
      end
      qf.update(project(), { force_open = true })
    end,
    {
      nargs = '?',
      complete = function()
        return qf.levels()
      end,
      desc = 'Set or cycle the lowest severity shown in the quickfix list',
    },
  },
  {
    'TexLog',
    function()
      info.log(project())
    end,
    { desc = 'Open the LaTeX log file' },
  },
  {
    'TexStatus',
    function()
      info.status(project())
    end,
    { desc = 'Report the compilation status of this project' },
  },
  {
    'TexStatusAll',
    function()
      info.status_all()
    end,
    { desc = 'Report the compilation status of all projects' },
  },
  {
    'TexInfo',
    function(opts)
      info.info(project(), opts.bang)
    end,
    { bang = true, desc = 'Show project information (! for the full dump)' },
  },
  {
    'TexToc',
    function()
      toc.open(project())
    end,
    { desc = 'Open the table of contents' },
  },
  {
    'TexTocToggle',
    function()
      toc.toggle(project())
    end,
    { desc = 'Toggle the table of contents' },
  },
  {
    'TexCountWords',
    count(false),
    { bang = true, range = true, desc = 'Count the words of the document or range (! for a report)' },
  },
  {
    'TexCountLetters',
    count(true),
    { bang = true, range = true, desc = 'Count the letters of the document or range (! for a report)' },
  },
  {
    'TexCite',
    function(opts)
      cite.cite(project(), opts.args)
    end,
    { nargs = '*', desc = 'Search online for a paper, add it to the bibliography and cite it' },
  },
  {
    'TexTikzPreview',
    function()
      require('nvim-tex.tikz.preview').preview(project())
    end,
    { desc = 'Compile the TikZ picture under the cursor on its own and show it' },
  },
  {
    'TexPreviewClose',
    function()
      require('nvim-tex.viewer.snacks').close()
    end,
    { desc = 'Remove the fragment preview from the buffer' },
  },
  {
    'TexTikzRename',
    function(opts)
      require('nvim-tex.tikz.nodes').rename(opts.args ~= '' and opts.args or nil)
    end,
    { nargs = '?', desc = 'Rename the TikZ node under the cursor throughout its picture' },
  },
  {
    'TexImaps',
    function()
      imaps.list()
    end,
    { desc = 'List the insert mode math mappings' },
  },
  {
    'TexReload',
    function()
      info.reload()
    end,
    { desc = 'Reload nvim-tex' },
  },
  {
    'TexReloadState',
    function()
      info.reload_state()
    end,
    { desc = 'Forget all cached project state' },
  },
  {
    'TexToggleMain',
    function()
      info.toggle_main(vim.api.nvim_get_current_buf())
    end,
    { desc = 'Toggle the main file between detected and current buffer' },
  },
  {
    'TexContextMenu',
    function()
      info.context_menu(project())
    end,
    { desc = 'Act on the citation, reference or include under the cursor' },
  },
  {
    'TexDocPackage',
    function()
      info.doc_package(project())
    end,
    { desc = 'Open the documentation of the package under the cursor' },
  },
  {
    'TexEnvSurround',
    function(opts)
      surround.env_surround_lines(opts.line1, opts.line2, opts.args ~= '' and opts.args or nil)
    end,
    { range = true, nargs = '?', desc = 'Surround the range with an environment' },
  },
}

function M.setup()
  for _, spec in ipairs(COMMANDS) do
    vim.api.nvim_create_user_command(spec[1], spec[2], spec[3])
  end
end

return M
