--- Buffer-local mappings.
---
--- The layout follows vimtex, with one difference: `<localleader>` is already
--- buffer-local, so the extra `l` layer vimtex uses is dropped.
--- `<localleader>ll` becomes `<localleader>l`, `<localleader>lc` becomes
--- `<localleader>c`, and so on.
local compiler = require('nvim-tex.compiler')
local config = require('nvim-tex.config')
local imaps = require('nvim-tex.imaps')
local info = require('nvim-tex.info')
local motions = require('nvim-tex.motions')
local project_mod = require('nvim-tex.project')
local qf = require('nvim-tex.qf')
local surround = require('nvim-tex.surround')
local textobj = require('nvim-tex.textobj')
local toc = require('nvim-tex.toc')
local viewer = require('nvim-tex.viewer')

local M = {}

---@return table
local function project()
  return project_mod.get(0)
end

--- `operatorfunc` for `<localleader>L` in normal mode.
---@param _ string
function M.op_compile_selected(_)
  local first, last = vim.fn.line("'["), vim.fn.line("']")
  compiler.compile_selected(project(), vim.api.nvim_buf_get_lines(0, first - 1, last, false))
end

--- `operatorfunc` for the operator variant of the environment surround.
---@param _ string
function M.op_env_surround(_)
  surround.env_surround_lines(vim.fn.line("'["), vim.fn.line("']"))
end

---@param bufnr integer
---@return fun(modes: string|string[], lhs: string, rhs: function|string, desc: string, extra: table|nil)
local function mapper(bufnr)
  return function(modes, lhs, rhs, desc, extra)
    vim.keymap.set(
      modes,
      lhs,
      rhs,
      vim.tbl_extend('force', {
        buffer = bufnr,
        silent = true,
        desc = 'nvim-tex: ' .. desc,
      }, extra or {})
    )
  end
end

--- The `<localleader>` group, mirroring vimtex minus the `l` layer.
---@param map function
---@param prefix string
local function leader_maps(map, prefix)
  map('n', prefix .. 'i', function()
    info.info(project(), false)
  end, 'info')
  map('n', prefix .. 'I', function()
    info.info(project(), true)
  end, 'info (full)')
  map('n', prefix .. 't', function()
    toc.open(project())
  end, 'open table of contents')
  map('n', prefix .. 'T', function()
    toc.toggle(project())
  end, 'toggle table of contents')
  map('n', prefix .. 'q', function()
    info.log(project())
  end, 'open the log file')
  map('n', prefix .. 'm', function()
    imaps.list()
  end, 'list the insert mode mappings')
  map('n', prefix .. 'v', function()
    viewer.view(project())
  end, 'view the PDF')
  map('n', prefix .. 'r', function()
    viewer.reverse_search(project())
  end, 'reverse search')
  map('n', prefix .. 'l', function()
    compiler.compile(project())
  end, 'start or stop compilation')
  map('n', prefix .. 'L', function()
    vim.o.operatorfunc = "v:lua.require'nvim-tex.keymaps'.op_compile_selected"
    return 'g@'
  end, 'compile the operated text', { expr = true })
  map('x', prefix .. 'L', function()
    vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))
    local first, last = vim.fn.line("'<"), vim.fn.line("'>")
    compiler.compile_selected(project(), vim.api.nvim_buf_get_lines(0, first - 1, last, false))
  end, 'compile the selection')
  map('n', prefix .. 'S', function()
    compiler.compile_single_shot(project())
  end, 'compile once')
  map('n', prefix .. 'k', function()
    compiler.stop(project())
  end, 'stop compilation')
  map('n', prefix .. 'K', function()
    compiler.stop_all()
  end, 'stop all compilations')
  map('n', prefix .. 'e', function()
    qf.update(project(), { force_open = true })
  end, 'show errors')
  map('n', prefix .. 'E', function()
    qf.cycle_level()
    qf.update(project(), { force_open = true })
  end, 'cycle the quickfix severity level')
  map('n', prefix .. 'o', function()
    compiler.show_output(project())
  end, 'show compiler output')
  map('n', prefix .. 'g', function()
    info.status(project())
  end, 'compilation status')
  map('n', prefix .. 'G', function()
    info.status_all()
  end, 'compilation status (all)')
  map('n', prefix .. 'c', function()
    compiler.clean(project(), false)
  end, 'clean auxiliary files')
  map('n', prefix .. 'C', function()
    compiler.clean(project(), true)
  end, 'clean all output')
  map('n', prefix .. 'x', function()
    info.reload()
  end, 'reload nvim-tex')
  map('n', prefix .. 'X', function()
    info.reload_state()
  end, 'reload project state')
  map('n', prefix .. 's', function()
    info.toggle_main(vim.api.nvim_get_current_buf())
  end, 'toggle main file')
  map('n', prefix .. 'a', function()
    info.context_menu(project())
  end, 'context menu')
end

--- Environment / command / delimiter editing, and the insert mode helpers.
---@param map function
local function surround_maps(map)
  map('n', 'dse', surround.env_delete, 'delete surrounding environment')
  map('n', 'dsc', surround.cmd_delete, 'delete surrounding command')
  map('n', 'ds$', surround.math_delete, 'delete surrounding math zone')
  map('n', 'dsd', surround.delim_delete, 'delete surrounding delimiter')

  map('n', 'cse', function()
    surround.env_change()
  end, 'change surrounding environment')
  map('n', 'csc', function()
    surround.cmd_change()
  end, 'change surrounding command')
  map('n', 'cs$', surround.math_change, 'change surrounding math zone')
  map('n', 'csd', surround.delim_change, 'change surrounding delimiter')

  map('n', 'tsf', function()
    surround.toggle_fraction(false)
  end, 'toggle fraction')
  map('x', 'tsf', function()
    surround.toggle_fraction(true)
  end, 'toggle fraction')
  map('n', 'tsc', surround.cmd_toggle_star, 'toggle starred command')
  map('n', 'tsb', surround.cmd_toggle_break, 'toggle trailing line break')
  map('n', 'tss', surround.env_toggle_star, 'toggle starred environment')
  map('n', 'tse', surround.env_toggle, 'toggle environment')
  map('n', 'ts$', surround.math_toggle, 'toggle inline/displayed math')
  map({ 'n', 'x' }, 'tsd', function()
    surround.delim_toggle_modifier(false)
  end, 'toggle delimiter modifier')
  map({ 'n', 'x' }, 'tsD', function()
    surround.delim_toggle_modifier(true)
  end, 'toggle delimiter modifier (reverse)')

  map('n', '<F6>', surround.env_surround_line, 'surround the line with an environment')
  map('x', '<F6>', surround.env_surround_visual, 'surround the selection with an environment')
  map('n', '<F7>', function()
    surround.cmd_create(false)
  end, 'wrap the word in a command')
  map('x', '<F7>', function()
    surround.cmd_create(true)
  end, 'wrap the selection in a command')
  map('i', '<F7>', surround.cmd_create_insert, 'turn the preceding word into a command')
  map('n', '<F8>', surround.delim_add_modifiers, 'add modifiers to delimiters')

  map('i', ']]', surround.delim_close, 'close the current environment or delimiter')
end

---@param bufnr integer
function M.attach(bufnr)
  local opts = config.get('mappings')
  if not opts.enabled then
    return
  end

  local map = mapper(bufnr)
  leader_maps(map, opts.prefix)

  if opts.motions then
    for lhs, fn in pairs(motions.map) do
      map({ 'n', 'x', 'o' }, lhs, fn, 'motion ' .. lhs)
    end
  end

  if opts.text_objects then
    for lhs, fn in pairs(textobj.map) do
      map({ 'x', 'o' }, lhs, fn, 'text object ' .. lhs)
    end
  end

  if opts.surround then
    surround_maps(map)
  end

  if opts.doc_package then
    map('n', 'K', function()
      info.doc_package(project())
    end, 'package documentation')
  end
end

return M
