--- Table of contents built from the tree-sitter parse tree.
---
--- The whole project is walked, following `\input`, `\include` and
--- `\subfile`, so the TOC covers a multi-file document even when only one of
--- its files is open.
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')
local ts = require('nvim-tex.ts')
local util = require('nvim-tex.util')

local M = {}

local LEVELS = {
  part = 0,
  chapter = 1,
  section = 2,
  subsection = 3,
  subsubsection = 4,
  paragraph = 5,
  subparagraph = 6,
}

--- Buffer holding the TOC, and the entries it currently shows.
local toc_buf = nil
local entries = {}

--- Current contents of `path`, preferring a loaded buffer over the file.
---@param path string
---@return string
local function contents(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr >= 0 and vim.api.nvim_buf_is_loaded(bufnr) then
    return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  end
  return table.concat(util.readlines(path), '\n')
end

--- Strip LaTeX markup from a title for display.
---@param text string
---@return string
local function clean(text)
  return vim.trim(text:gsub('\\%a+%s*{(.-)}', '%1'):gsub('[{}]', ''):gsub('\\%a+%s*', ''):gsub('%s+', ' '))
end

--- Resolve an `\input{foo}` path relative to `dir`.
---@param dir string
---@param path string
---@return string|nil
local function resolve_include(dir, path)
  local candidates = { path, path .. '.tex' }
  for _, candidate in ipairs(candidates) do
    local full = candidate:match('^[/~]') and util.normalize(candidate) or util.join(dir, candidate)
    if util.is_file(full) then
      return util.normalize(full)
    end
  end
  return nil
end

---@param file string
---@param root string
---@param out table[]
---@param seen table<string, boolean>
---@param depth integer
local function walk_file(file, root, out, seen, depth)
  if seen[file] or depth > 8 then
    return
  end
  seen[file] = true

  local source = contents(file)
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, 'latex')
  if not ok or not parser then
    return
  end
  local tree = parser:parse()[1]
  if not tree then
    return
  end

  local opts = config.get('toc')

  ---@param node TSNode
  local function visit(node)
    local kind = node:type()

    if LEVELS[kind] then
      local title = node:named_child(0)
      local row = select(1, node:range())
      out[#out + 1] = {
        file = file,
        lnum = row + 1,
        level = LEVELS[kind],
        kind = kind,
        title = title and clean(vim.treesitter.get_node_text(title, source)) or kind,
      }
    elseif kind == 'latex_include' then
      local row = select(1, node:range())
      local path_node = nil
      for child in node:iter_children() do
        if child:type():match('^curly_group_path') then
          for grand in child:iter_children() do
            if grand:type() == 'path' then
              path_node = grand
              break
            end
          end
        end
      end
      if path_node then
        local raw = vim.treesitter.get_node_text(path_node, source)
        local target = resolve_include(vim.fs.dirname(file), raw)
        if opts.show_includes then
          out[#out + 1] = {
            file = file,
            lnum = row + 1,
            level = 7,
            kind = 'include',
            title = 'include: ' .. raw,
          }
        end
        if target then
          walk_file(target, root, out, seen, depth + 1)
        end
      end
      return
    elseif ts.ENVIRONMENT[kind] then
      local name = ts.env_name(node, source)
      if name == 'frame' then
        local row = select(1, node:range())
        local title = ''
        local begin_node = ts.env_parts(node)
        if begin_node then
          local sibling = begin_node:next_named_sibling()
          if sibling and sibling:type() == 'curly_group' then
            title = clean(vim.treesitter.get_node_text(sibling, source))
          end
        end
        out[#out + 1] = {
          file = file,
          lnum = row + 1,
          level = 6,
          kind = 'frame',
          title = 'frame: ' .. (title ~= '' and title or '(untitled)'),
        }
      end
    elseif kind == 'label_definition' and opts.show_labels then
      local row = select(1, node:range())
      out[#out + 1] = {
        file = file,
        lnum = row + 1,
        level = 7,
        kind = 'label',
        title = 'label: ' .. clean(vim.treesitter.get_node_text(node, source):gsub('^\\label', '')),
      }
    elseif kind == 'line_comment' and opts.show_todos then
      local text = vim.treesitter.get_node_text(node, source)
      local todo = text:match('%%+%s*(TODO.*)$') or text:match('%%+%s*(FIXME.*)$') or text:match('%%+%s*(XXX.*)$')
      if todo then
        local row = select(1, node:range())
        out[#out + 1] = { file = file, lnum = row + 1, level = 7, kind = 'todo', title = vim.trim(todo) }
      end
    end

    for child in node:iter_children() do
      if child:named() then
        visit(child)
      end
    end
  end

  visit(tree:root())
end

--- Build the TOC entries for `project`.
---@param project table
---@return table[]
function M.build(project)
  local out = {}
  walk_file(project.main, project.root, out, {}, 0)
  return out
end

---@param entry table
---@return string
local function render(entry)
  return string.rep('  ', entry.level) .. entry.title
end

--- Jump to the entry under the cursor in the TOC window.
local function jump()
  local index = vim.api.nvim_win_get_cursor(0)[1]
  local entry = entries[index]
  if not entry then
    return
  end

  local close = config.get('toc', 'close_after_jump')
  local toc_win = vim.api.nvim_get_current_win()

  -- Find a window that is not the TOC to jump in.
  local target_win
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= toc_win then
      target_win = win
      break
    end
  end
  if not target_win then
    vim.cmd('vsplit')
    target_win = vim.api.nvim_get_current_win()
  end

  vim.api.nvim_set_current_win(target_win)
  if util.normalize(vim.api.nvim_buf_get_name(0)) ~= entry.file then
    vim.cmd('edit ' .. vim.fn.fnameescape(entry.file))
  end
  vim.api.nvim_win_set_cursor(0, { math.min(entry.lnum, vim.api.nvim_buf_line_count(0)), 0 })
  vim.cmd('normal! zz')

  if close and vim.api.nvim_win_is_valid(toc_win) then
    vim.api.nvim_win_close(toc_win, true)
  end
end

---@param project table
---@return integer bufnr
local function create_buffer(project)
  entries = M.build(project)

  local lines = {}
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = render(entry)
  end
  if #lines == 0 then
    lines = { '(no sections found)' }
  end

  if not toc_buf or not vim.api.nvim_buf_is_valid(toc_buf) then
    toc_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(toc_buf, 'nvim-tex://toc')
  end

  vim.bo[toc_buf].modifiable = true
  vim.api.nvim_buf_set_lines(toc_buf, 0, -1, false, lines)
  vim.bo[toc_buf].modifiable = false
  vim.bo[toc_buf].buftype = 'nofile'
  vim.bo[toc_buf].bufhidden = 'hide'
  vim.bo[toc_buf].swapfile = false
  vim.bo[toc_buf].filetype = 'nvimtextoc'

  vim.keymap.set('n', '<CR>', jump, { buffer = toc_buf, nowait = true })
  vim.keymap.set('n', '<2-LeftMouse>', jump, { buffer = toc_buf, nowait = true })
  vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = toc_buf, nowait = true })
  vim.keymap.set('n', 'r', function()
    M.open(project)
  end, { buffer = toc_buf, nowait = true })

  return toc_buf
end

---@return integer|nil
function M.window()
  if toc_buf and vim.api.nvim_buf_is_valid(toc_buf) then
    local win = vim.fn.bufwinid(toc_buf)
    return win ~= -1 and win or nil
  end
  return nil
end

---@param project table
function M.open(project)
  local bufnr = create_buffer(project)
  local opts = config.get('toc')

  local win = M.window()
  if win then
    vim.api.nvim_set_current_win(win)
    return
  end

  if opts.split == 'tab' then
    vim.cmd('tabnew')
  elseif opts.split == 'split' then
    vim.cmd('botright split')
  else
    vim.cmd('topleft vsplit')
  end

  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  if opts.split == 'split' then
    vim.api.nvim_win_set_height(win, opts.height)
  elseif opts.split == 'vsplit' then
    vim.api.nvim_win_set_width(win, opts.width)
  end
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
end

---@param project table
function M.toggle(project)
  local win = M.window()
  if win then
    vim.api.nvim_win_close(win, true)
  else
    M.open(project)
  end
end

return M
