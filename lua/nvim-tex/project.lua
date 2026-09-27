--- Project (main file) detection and the per-project state registry.
---
--- Every LaTeX buffer belongs to exactly one project, identified by the
--- absolute path of its main file. All long lived state -- the running
--- compiler job, the viewer handle, the collected output -- hangs off that
--- project, so several buffers of the same document share one compilation.
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = {}

--- main path -> project
---@type table<string, table>
M.projects = {}

--- bufnr -> main path
---@type table<integer, string>
local buf_main = {}

local ROOT_PATTERNS = {
  '%%%s*!%s*TEX%s+root%s*=%s*(.+)$',
  '%%%s*!%s*[Tt][Ee][Xx]%s+root%s*=%s*(.+)$',
}

local PROGRAM_PATTERNS = {
  '%%%s*!%s*[Tt][Ee][Xx]%s+program%s*=%s*(.+)$',
  '%%%s*!%s*[Tt][Ee][Xx]%s+[Tt][Ss]%-program%s*=%s*(.+)$',
}

---@param lines string[]
---@param patterns string[]
---@return string|nil
local function match_directive(lines, patterns)
  for _, line in ipairs(lines) do
    for _, pat in ipairs(patterns) do
      local value = line:match(pat)
      if value then
        return vim.trim(value)
      end
    end
  end
  return nil
end

--- Directive lines are only honoured near the top or bottom of a file.
---@param bufnr integer
---@return string[]
local function directive_lines(bufnr)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local head = vim.api.nvim_buf_get_lines(bufnr, 0, math.min(5, total), false)
  local tail = vim.api.nvim_buf_get_lines(bufnr, math.max(0, total - 5), -1, false)
  return vim.list_extend(head, tail)
end

--- A document root is what holds the `\\begin{document}`. Its `\\documentclass`
--- may well come from a shared preamble that is `\\input` by several
--- documents -- and that preamble cannot be compiled on its own.
---@param lines string[]
---@return boolean
local function is_root(lines)
  for _, line in ipairs(lines) do
    local code = line:gsub('^(.-)%%.*$', '%1')
    if code:find('\\begin%s*{document}') then
      return true
    end
  end
  return false
end

--- Does `candidate` pull `target` in via \input, \include or \subfile?
---@param candidate string
---@param target string
---@return boolean
local function includes(candidate, target)
  local stem = vim.fn.fnamemodify(target, ':t:r')
  local pattern = '\\%a*[iI]nput{[^}]*' .. vim.pesc(stem)
  for _, line in ipairs(util.readlines(candidate)) do
    if
      line:find(pattern)
      or line:find('\\include{[^}]*' .. vim.pesc(stem))
      or line:find('\\subfile{[^}]*' .. vim.pesc(stem))
    then
      return true
    end
  end
  return false
end

--- Walk up from `dir` looking for a file that looks like the document root.
---@param dir string
---@param target string
---@return string|nil
local function search_upwards(dir, target)
  local current = dir
  for _ = 1, 5 do
    local candidates = vim.fn.glob(util.join(current, '*.tex'), false, true)
    -- Prefer a root that actually references us, fall back to any root.
    local fallback = nil
    for _, candidate in ipairs(candidates) do
      if util.normalize(candidate) ~= target and is_root(util.readlines(candidate)) then
        if includes(candidate, target) then
          return util.normalize(candidate)
        end
        fallback = fallback or util.normalize(candidate)
      end
    end
    if fallback then
      return fallback
    end

    -- `.latexmain` marker files, as used by vimtex and latex-suite.
    local markers = vim.fn.glob(util.join(current, '*.latexmain'), false, true)
    if #markers > 0 then
      return util.normalize((markers[1]:gsub('%.latexmain$', '')))
    end

    local parent = vim.fs.dirname(current)
    if not parent or parent == current then
      break
    end
    current = parent
  end
  return nil
end

--- The main file of a known project that pulls in `file`. The project of the
--- alternate buffer wins, as that is usually where `file` was opened from.
---@param file string
---@return string|nil
local function open_project_including(file)
  local mains = {}
  for main in pairs(M.projects) do
    if main ~= file and includes(main, file) then
      mains[#mains + 1] = main
    end
  end
  if #mains == 0 then
    return nil
  end
  local alt = buf_main[vim.fn.bufnr('#')]
  if alt and vim.tbl_contains(mains, alt) then
    return alt
  end
  table.sort(mains)
  return mains[1]
end

--- Resolve the main file for `bufnr`.
---@param bufnr integer
---@return string
function M.detect_main(bufnr)
  local file = util.normalize(vim.api.nvim_buf_get_name(bufnr))

  -- 1. Buffer variable set by the user or by `:TexToggleMain`.
  local ok, override = pcall(vim.api.nvim_buf_get_var, bufnr, 'tex_main')
  if ok and type(override) == 'string' and override ~= '' then
    return util.normalize(override)
  end

  -- 2. Explicit configuration.
  local configured = config.get('main_file')
  if type(configured) == 'function' then
    configured = configured(bufnr)
  end
  if type(configured) == 'string' and configured ~= '' then
    return util.normalize(configured)
  end

  -- 3. A `% !TEX root = ...` directive.
  local root = match_directive(directive_lines(bufnr), ROOT_PATTERNS)
  if root then
    if not root:match('^[/~]') then
      root = util.join(vim.fs.dirname(file), root)
    end
    if not root:match('%.%a+$') then
      root = root .. '.tex'
    end
    return util.normalize(root)
  end

  -- 4. The buffer itself is a document root.
  if is_root(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) then
    return file
  end

  -- 5. An already open project that includes this file, e.g. the document a
  -- shared header was opened from.
  local open = file ~= '' and open_project_including(file) or nil
  if open then
    return open
  end

  -- 6. Look for a root in this and the parent directories.
  local found = file ~= '' and search_upwards(vim.fs.dirname(file), file) or nil
  return found or file
end

---@param main string
---@param bufnr integer
---@return table
local function new_project(main, bufnr)
  local backend = config.compiler_options()
  local project = {
    main = main,
    root = vim.fs.dirname(main),
    name = vim.fn.fnamemodify(main, ':t:r'),
    tex_program = match_directive(directive_lines(bufnr), PROGRAM_PATTERNS),
    compiler = nil, -- set by nvim-tex.compiler
    viewer = nil, -- set by nvim-tex.viewer
    output = {}, -- captured compiler output
  }

  local file_info = {
    root = project.root,
    target = main,
    target_basename = vim.fn.fnamemodify(main, ':t'),
    target_name = project.name,
    jobname = project.name,
  }
  project.file_info = file_info

  ---@param value any
  ---@return string
  local function directory(value)
    local resolved = util.resolve(value, file_info) or ''
    if resolved == '' then
      return project.root
    end
    if not resolved:match('^[/~]') then
      resolved = util.join(project.root, resolved)
    end
    return util.normalize(resolved)
  end

  -- `$VIMTEX_OUTPUT_DIRECTORY` is respected for drop-in compatibility with
  -- existing setups and with latexmk wrappers that already export it.
  local env_out = vim.env.VIMTEX_OUTPUT_DIRECTORY or vim.env.NVIM_TEX_OUTPUT_DIRECTORY
  local out_set = env_out ~= nil or (util.resolve(backend.out_dir, file_info) or '') ~= ''
  local aux_set = env_out ~= nil or (util.resolve(backend.aux_dir, file_info) or '') ~= ''
  project.out_dir = env_out and util.normalize(env_out) or directory(backend.out_dir)
  project.out_dir_set = out_set
  -- Without an aux directory of its own the log is written next to the PDF:
  -- latexmk defaults `-auxdir` to `-outdir`, and tectonic has no aux
  -- directory at all.
  project.aux_dir = (aux_set and not env_out) and directory(backend.aux_dir) or project.out_dir
  project.aux_dir_set = aux_set

  return project
end

--- Get (creating if needed) the project for `bufnr`.
---@param bufnr integer|nil
---@return table
function M.get(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr

  local main = buf_main[bufnr]
  if not main or not M.projects[main] then
    main = M.detect_main(bufnr)
    buf_main[bufnr] = main
    if not M.projects[main] then
      M.projects[main] = new_project(main, bufnr)
    end
  end
  return M.projects[main]
end

--- Drop cached detection for `bufnr` and redetect on next access.
---@param bufnr integer|nil
function M.invalidate(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  buf_main[bufnr] = nil
end

--- Forget a project entirely (used by `:TexReloadState`).
---@param project table
function M.forget(project)
  for bufnr, main in pairs(buf_main) do
    if main == project.main then
      buf_main[bufnr] = nil
    end
  end
  M.projects[project.main] = nil
end

--- All buffers currently associated with `project`.
---@param project table
---@return integer[]
function M.buffers(project)
  local out = {}
  for bufnr, main in pairs(buf_main) do
    if main == project.main and vim.api.nvim_buf_is_valid(bufnr) then
      out[#out + 1] = bufnr
    end
  end
  return out
end

--- The compiled PDF (or DVI/PS) for `project`.
---@param project table
---@param ext string|nil defaults to 'pdf'
---@return string
function M.output_file(project, ext)
  return util.join(project.out_dir, project.name .. '.' .. (ext or 'pdf'))
end

--- The LaTeX log file, which lives in the aux directory.
---@param project table
---@return string
function M.log_file(project)
  return util.join(project.aux_dir, project.name .. '.log')
end

--- Where compiler output and other scratch data is cached.
---@param project table
---@return string
function M.cache_dir(project)
  local hash = vim.fn.sha256(project.main):sub(1, 16)
  local dir = util.join(config.get('cache_root'), project.name .. '-' .. hash)
  util.mkdir(dir)
  return dir
end

return M
