--- Informational commands: `:TexInfo`, `:TexStatus`, the context menu and
--- package documentation lookup.
local compiler = require('nvim-tex.compiler')
local config = require('nvim-tex.config')
local lsp = require('nvim-tex.lsp')
local project_mod = require('nvim-tex.project')
local ts = require('nvim-tex.ts')
local util = require('nvim-tex.util')
local viewer = require('nvim-tex.viewer')

local M = {}

---@param project table
---@param full boolean
---@return string[]
local function info_lines(project, full)
  local lines = {
    'nvim-tex',
    '',
    'project',
    '  main file:   ' .. vim.fn.fnamemodify(project.main, ':~'),
    '  root:        ' .. vim.fn.fnamemodify(project.root, ':~'),
    '  out dir:     ' .. vim.fn.fnamemodify(project.out_dir, ':~'),
    '  aux dir:     ' .. vim.fn.fnamemodify(project.aux_dir, ':~'),
    '  tex program: ' .. (project.tex_program or '(default)'),
    '  pdf:         ' .. vim.fn.fnamemodify(project_mod.output_file(project), ':~'),
    '',
    'compiler',
    '  method:      ' .. tostring(config.get('compiler', 'method')),
    '  state:       ' .. compiler.status_line(project):gsub('^.-: ', ''),
  }

  if project.qf_errors or project.qf_warnings then
    lines[#lines + 1] = ('  diagnostics: %d errors, %d warnings'):format(project.qf_errors or 0, project.qf_warnings or 0)
  end
  if project.compiler then
    lines[#lines + 1] = '  command:     ' .. table.concat(project.compiler.cmd, ' ')
  end

  local client = lsp.client()
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'lsp'
  lines[#lines + 1] = '  client:      ' .. (client and (client.name .. ' (id ' .. client.id .. ')') or 'not attached')
  if client then
    lines[#lines + 1] = '  root:        ' .. vim.fn.fnamemodify(client.root_dir or '', ':~')
  end

  lines[#lines + 1] = ''
  lines[#lines + 1] = 'treesitter'
  lines[#lines + 1] = '  parser:      ' .. (ts.parser(0) and 'latex (active)' or 'unavailable')

  lines[#lines + 1] = ''
  lines[#lines + 1] = 'viewer'
  lines[#lines + 1] = '  method:      ' .. tostring(config.get('view', 'method'))
  lines[#lines + 1] = '  running:     ' .. (viewer.is_running(project) and (project.viewer.backend .. ' (pid ' .. tostring(project.viewer.pid) .. ')') or 'no')

  if full then
    local toc = require('nvim-tex.toc').build(project)
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'documents'
    local seen = {}
    for _, entry in ipairs(toc) do
      if not seen[entry.file] then
        seen[entry.file] = true
        lines[#lines + 1] = '  ' .. vim.fn.fnamemodify(entry.file, ':~:.')
      end
    end

    lines[#lines + 1] = ''
    lines[#lines + 1] = 'configuration'
    for _, chunk in ipairs(vim.split(vim.inspect(config.get()), '\n', { plain = true })) do
      lines[#lines + 1] = '  ' .. chunk
    end
  end

  return lines
end

---@param project table
---@param full boolean|nil
function M.info(project, full)
  util.scratch('nvim-tex://info', info_lines(project, full or false), { height = full and 25 or 20 })
end

---@param project table
function M.status(project)
  util.info(compiler.status_line(project))
end

function M.status_all()
  local lines = {}
  for _, project in pairs(project_mod.projects) do
    lines[#lines + 1] = compiler.status_line(project)
  end
  if #lines == 0 then
    util.info('no projects')
    return
  end
  util.scratch('nvim-tex://status', lines, { height = math.min(#lines + 1, 12) })
end

--- Text of the first `{...}` argument of `node`.
---@param node TSNode
---@return string|nil
local function first_arg_text(node)
  for child in node:iter_children() do
    if child:type():match('^curly_group') then
      return vim.trim(vim.treesitter.get_node_text(child, 0):sub(2, -2))
    end
  end
  return nil
end

--- Search the project's `.bib` files for `key` and jump to it.
---@param project table
---@param key string
---@return boolean found
local function goto_bib_entry(project, key)
  local bibs = vim.fn.globpath(project.root, '**/*.bib', false, true)
  for _, bib in ipairs(bibs) do
    local lnum = 0
    for _, line in ipairs(util.readlines(bib)) do
      lnum = lnum + 1
      if line:find('@%w+%s*{%s*' .. vim.pesc(key) .. '%s*,') then
        vim.cmd('edit ' .. vim.fn.fnameescape(bib))
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
        vim.cmd('normal! zz')
        return true
      end
    end
  end
  return false
end

--- Jump to `\label{name}` anywhere in the project.
---@param project table
---@param name string
---@return boolean found
local function goto_label(project, name)
  local files = { project.main }
  for _, entry in ipairs(require('nvim-tex.toc').build(project)) do
    if not vim.tbl_contains(files, entry.file) then
      files[#files + 1] = entry.file
    end
  end

  for _, file in ipairs(files) do
    local lnum = 0
    for _, line in ipairs(util.readlines(file)) do
      lnum = lnum + 1
      if line:find('\\label%s*{%s*' .. vim.pesc(name) .. '%s*}') then
        vim.cmd('edit ' .. vim.fn.fnameescape(file))
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
        vim.cmd('normal! zz')
        return true
      end
    end
  end
  return false
end

--- Act on whatever is under the cursor: citations, references, includes and
--- packages get a dedicated action, everything else falls back to the LSP.
---@param project table
function M.context_menu(project)
  local bufnr = vim.api.nvim_get_current_buf()
  local node = ts.node_at_cursor(bufnr)

  local citation = ts.ancestor(node, { citation = true })
  if citation then
    local key = first_arg_text(citation)
    if key then
      key = vim.split(key, ',', { plain = true })[1]
      if goto_bib_entry(project, vim.trim(key)) then
        return
      end
      util.warn('no bib entry for ' .. key)
      return
    end
  end

  local reference = ts.ancestor(node, { label_reference = true })
  if reference then
    local name = first_arg_text(reference)
    if name then
      name = vim.split(name, ',', { plain = true })[1]
      if goto_label(project, vim.trim(name)) then
        return
      end
      util.warn('no label ' .. name)
      return
    end
  end

  local include = ts.ancestor(node, function(n)
    return n:type():match('_include$') ~= nil
  end)
  if include then
    local kind = include:type()
    if kind == 'package_include' or kind == 'class_include' then
      M.doc_package(project)
      return
    end
    local path = first_arg_text(include)
    if path then
      local target = path:match('^[/~]') and path or util.join(vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)), path)
      for _, candidate in ipairs({ target, target .. '.tex' }) do
        if util.is_file(candidate) then
          vim.cmd('edit ' .. vim.fn.fnameescape(candidate))
          return
        end
      end
      util.warn('cannot open ' .. path)
      return
    end
  end

  if lsp.client(bufnr) then
    vim.lsp.buf.definition()
    return
  end
  util.info('nothing to do here')
end

--- `K`: open the documentation of the package or command under the cursor.
---@param project table
function M.doc_package(project)
  local bufnr = vim.api.nvim_get_current_buf()
  local node = ts.node_at_cursor(bufnr)

  local names = {}
  local include = ts.ancestor(node, function(n)
    return n:type() == 'package_include' or n:type() == 'class_include'
  end)
  if include then
    -- `\usepackage{a,b}` can name several packages; ask which one.
    local text = first_arg_text(include)
    for _, name in ipairs(vim.split(text or '', ',', { plain = true })) do
      name = vim.trim(name)
      if name ~= '' then
        names[#names + 1] = name
      end
    end
  else
    local word = vim.fn.expand('<cword>')
    if word ~= '' then
      names[#names + 1] = word
    end
  end

  if #names == 0 then
    util.warn('nothing under the cursor')
    return
  end

  local function open(name)
    if not util.executable('texdoc') then
      -- Without texdoc, hover is the next best thing.
      if lsp.client(bufnr) then
        vim.lsp.buf.hover()
      else
        util.warn("'texdoc' not found")
      end
      return
    end
    vim.system({ 'texdoc', name }, { detach = true })
    util.info('texdoc ' .. name)
  end

  if #names == 1 then
    open(names[1])
  else
    vim.ui.select(names, { prompt = 'Package documentation:' }, function(choice)
      if choice then
        open(choice)
      end
    end)
  end
end

--- Show the `.log` file of the last compilation.
---@param project table
function M.log(project)
  local logfile = project_mod.log_file(project)
  if not util.is_file(logfile) then
    util.warn('no log file: ' .. vim.fn.fnamemodify(logfile, ':~:.'))
    return
  end
  vim.cmd('botright split ' .. vim.fn.fnameescape(logfile))
  vim.bo.filetype = 'log'
end

--- Reload the plugin's Lua modules, keeping the user configuration.
function M.reload()
  local options = vim.deepcopy(config.get())
  for name, _ in pairs(package.loaded) do
    if name:match('^nvim%-tex') then
      package.loaded[name] = nil
    end
  end
  require('nvim-tex').setup(options)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(config.get('filetypes'), vim.bo[bufnr].filetype) then
      require('nvim-tex').attach(bufnr)
    end
  end
  util.info('reloaded')
end

--- Drop all cached project state and redetect.
function M.reload_state()
  for _, project in pairs(vim.deepcopy(project_mod.projects)) do
    local live = project_mod.projects[project.main]
    if live then
      project_mod.forget(live)
    end
  end
  util.info('project state cleared')
end

--- Cycle the main file between the detected one and the current buffer.
---@param bufnr integer
function M.toggle_main(bufnr)
  local current = vim.api.nvim_buf_get_name(bufnr)
  local ok, existing = pcall(vim.api.nvim_buf_get_var, bufnr, 'tex_main')
  if ok and existing and existing ~= '' then
    vim.api.nvim_buf_del_var(bufnr, 'tex_main')
    project_mod.invalidate(bufnr)
    util.info('main file: ' .. vim.fn.fnamemodify(project_mod.get(bufnr).main, ':~:.') .. ' (detected)')
  else
    vim.api.nvim_buf_set_var(bufnr, 'tex_main', current)
    project_mod.invalidate(bufnr)
    util.info('main file: ' .. vim.fn.fnamemodify(current, ':~:.') .. ' (this buffer)')
  end
end

return M
