--- The `ds*` / `cs*` / `ts*` editing mappings plus <F6>, <F7> and <F8>.
---
--- Deleting, changing and toggling all work on the tree-sitter node under the
--- cursor, so they are robust against nesting and line breaks.
local config = require('nvim-tex.config')
local ts = require('nvim-tex.ts')
local util = require('nvim-tex.util')

local M = {}

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)

---@param row integer 1-indexed
---@return string
local function line_at(row)
  return vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
end

--- Replace a tree-sitter range (0-indexed, end-exclusive) with `text`.
---@param sr integer
---@param sc integer
---@param er integer
---@param ec integer
---@param text string
local function replace(sr, sc, er, ec, text)
  vim.api.nvim_buf_set_text(0, sr, sc, er, ec, vim.split(text, '\n', { plain = true }))
end

--- Remove a node. When it is alone on its line, the line goes too.
---@param node TSNode
local function remove_node(node)
  local sr, sc, er, ec = node:range()
  local before = line_at(sr + 1):sub(1, sc)
  local after = line_at(er + 1):sub(ec + 1)
  if before:match('^%s*$') and after:match('^%s*$') then
    vim.api.nvim_buf_set_lines(0, sr, er + 1, false, {})
  else
    replace(sr, sc, er, ec, '')
  end
end

--- Ask for input, pre-filled with `default`.
---@param prompt string
---@param default string|nil
---@param completion string|nil
---@return string|nil
local function ask(prompt, default, completion)
  local opts = { prompt = prompt, default = default or '' }
  if completion then
    opts.completion = completion
  end
  local ok, answer = pcall(vim.fn.input, opts)
  if not ok or answer == nil or answer == '' then
    return nil
  end
  return vim.trim(answer)
end

-- ---------------------------------------------------------------------------
-- Environments
-- ---------------------------------------------------------------------------

--- The innermost environment around the cursor, `document` excluded.
---@return TSNode|nil
local function env_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local node = ts.node_at_cursor(bufnr)
  while node do
    node = ts.ancestor(node, ts.ENVIRONMENT)
    if not node then
      return nil
    end
    if ts.env_name(node, bufnr) ~= 'document' then
      return node
    end
    node = node:parent()
  end
  return nil
end

--- The `curly_group_text` holding the environment name.
---@param part TSNode
---@return TSNode|nil
local function env_name_group(part)
  for child in part:iter_children() do
    if child:type():match('^curly_group_text') then
      return child
    end
  end
  return nil
end

function M.env_delete()
  local node = env_at_cursor()
  if not node then
    util.warn('no surrounding environment')
    return
  end
  local begin_node, end_node = ts.env_parts(node)
  if not (begin_node and end_node) then
    return
  end
  -- Later range first so the earlier one stays valid.
  remove_node(end_node)
  remove_node(begin_node)
end

---@param new_name string|nil when nil the user is prompted
function M.env_change(new_name)
  local bufnr = vim.api.nvim_get_current_buf()
  local node = env_at_cursor()
  if not node then
    util.warn('no surrounding environment')
    return
  end
  local current = ts.env_name(node, bufnr)
  new_name = new_name or ask('Change environment: ', current)
  if not new_name or new_name == current then
    return
  end

  local begin_node, end_node = ts.env_parts(node)
  for _, part in ipairs({ end_node, begin_node }) do
    local group = part and env_name_group(part)
    if group then
      local sr, sc, er, ec = group:range()
      replace(sr, sc, er, ec, '{' .. new_name .. '}')
    end
  end
end

function M.env_toggle_star()
  local bufnr = vim.api.nvim_get_current_buf()
  local node = env_at_cursor()
  if not node then
    util.warn('no surrounding environment')
    return
  end
  local name = ts.env_name(node, bufnr)
  if not name then
    return
  end
  M.env_change(name:match('%*$') and name:gsub('%*$', '') or (name .. '*'))
end

function M.env_toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  local node = env_at_cursor()
  if not node then
    util.warn('no surrounding environment')
    return
  end
  local name = ts.env_name(node, bufnr)
  if not name then
    return
  end

  -- The star is carried over, so `align*` toggles to `gather*`.
  local base, star = name:match('^(.-)(%*?)$')
  local target = config.get('edit', 'env_toggle_map')[base]
  if not target then
    util.warn(("no toggle target for environment '%s'"):format(name))
    return
  end
  M.env_change(target .. star)
end

--- The innermost math zone around the cursor.
---@return TSNode|nil
local function math_at_cursor()
  return ts.ancestor(ts.node_at_cursor(0), ts.MATH)
end

--- Start and end delimiter nodes of a math zone.
---@param node TSNode
---@return TSNode|nil, TSNode|nil
local function math_delims(node)
  if node:type() == 'math_environment' then
    return ts.env_parts(node)
  end
  return node:child(0), node:child(node:child_count() - 1)
end

function M.math_delete()
  local node = math_at_cursor()
  if not node then
    util.warn('not inside a math zone')
    return
  end
  local open, close = math_delims(node)
  if not (open and close) or open:id() == close:id() then
    return
  end
  remove_node(close)
  remove_node(open)
end

function M.math_change()
  local node = math_at_cursor()
  if not node then
    util.warn('not inside a math zone')
    return
  end
  if node:type() == 'math_environment' then
    M.env_change()
    return
  end

  local answer = ask('Change math zone to ($, \\[, or an environment name): ')
  if not answer then
    return
  end

  local open, close = math_delims(node)
  local sr, sc = node:range()
  local _, _, er, ec = node:range()
  local isr, isc, ier, iec
  do
    local _, _, a, b = open:range()
    isr, isc = a, b
    local c, d = close:range()
    ier, iec = c, d
  end
  local body = table.concat(vim.api.nvim_buf_get_text(0, isr, isc, ier, iec, {}), '\n')

  local opening, closing
  if answer == '$' then
    opening, closing = '$', '$'
  elseif answer == '$$' then
    opening, closing = '$$', '$$'
  elseif answer == '\\[' or answer == '[' then
    opening, closing = '\\[', '\\]'
  elseif answer == '\\(' or answer == '(' then
    opening, closing = '\\(', '\\)'
  else
    opening, closing = '\\begin{' .. answer .. '}', '\\end{' .. answer .. '}'
  end

  replace(sr, sc, er, ec, opening .. body .. closing)
end

function M.math_toggle()
  local node = math_at_cursor()
  if not node then
    util.warn('not inside a math zone')
    return
  end

  local open = math_delims(node)
  if not open then
    return
  end
  local current = vim.treesitter.get_node_text(open, 0)
  local target = config.get('edit', 'env_toggle_math_map')[current]
  if not target then
    util.warn(("no math toggle target for '%s'"):format(current))
    return
  end

  local sr, sc, er, ec = node:range()
  local _, close = math_delims(node)
  local _, _, isr, isc = open:range()
  local ier, iec = close:range()
  local body = vim.trim(table.concat(vim.api.nvim_buf_get_text(0, isr, isc, ier, iec, {}), '\n'))

  if target == '\\[' then
    -- Displayed math goes on its own lines, like vimtex does it.
    local indent = line_at(sr + 1):match('^%s*') or ''
    replace(sr, sc, er, ec, '\\[\n' .. indent .. '  ' .. body .. '\n' .. indent .. '\\]')
  elseif target == '$' then
    replace(sr, sc, er, ec, '$' .. body .. '$')
  else
    replace(sr, sc, er, ec, target .. body .. target)
  end
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

--- The command around the cursor.
---
--- Sectioning commands are not commands as far as the `ac`/`ic` text objects
--- are concerned, but `tsc` and `csc` should still reach `\\section`.
---@param include_sections boolean|nil
---@return TSNode|nil
local function cmd_at_cursor(include_sections)
  return ts.ancestor(ts.node_at_cursor(0), function(n)
    return ts.is_command(n) or (include_sections == true and ts.SECTION[n:type()] == true)
  end)
end

--- The first `{...}` argument of a command.
---@param node TSNode
---@return TSNode|nil
local function first_arg(node)
  for child in node:iter_children() do
    if child:type():match('^curly_group') then
      return child
    end
  end
  return nil
end

function M.cmd_delete()
  local node = cmd_at_cursor()
  if not node then
    util.warn('no surrounding command')
    return
  end

  local name = ts.command_name_node(node)
  local arg = first_arg(node)
  if arg then
    -- Drop the braces of the first argument, keeping its contents.
    local asr, asc, aer, aec = arg:range()
    replace(aer, aec - 1, aer, aec, '')
    replace(asr, asc, asr, asc + 1, '')
  end
  if name then
    local sr, sc, er, ec = name:range()
    replace(sr, sc, er, ec, '')
  end
end

---@param new_name string|nil
---@param node TSNode|nil command to act on; looked up when omitted
function M.cmd_change(new_name, node)
  node = node or cmd_at_cursor(true)
  if not node then
    util.warn('no surrounding command')
    return
  end
  local name = ts.command_name_node(node)
  if not name then
    return
  end

  local current = vim.treesitter.get_node_text(name, 0):gsub('^\\', '')
  new_name = new_name or ask('Change command: ', current)
  if not new_name or new_name == current then
    return
  end
  local sr, sc, er, ec = name:range()
  replace(sr, sc, er, ec, '\\' .. (new_name:gsub('^\\', '')))
end

function M.cmd_toggle_star()
  local node = cmd_at_cursor(true)
  if not node then
    util.warn('no surrounding command')
    return
  end
  local name = ts.command_name_node(node)
  if not name then
    return
  end

  local current = vim.treesitter.get_node_text(name, 0):gsub('^\\', '')
  local base = current:gsub('%*$', '')
  local allowed = config.get('edit', 'toggle_star_cmds')
  if allowed and not vim.tbl_contains(allowed, base) then
    util.warn(("'%s' is not in edit.toggle_star_cmds"):format(base))
    return
  end
  M.cmd_change(current:match('%*$') and base or (base .. '*'), node)
end

--- `tsc` and `tss` combined: act on whichever of command / environment is
--- closer to the cursor.
function M.toggle_star_agnostic()
  local cmd = cmd_at_cursor(true)
  local env = env_at_cursor()
  if cmd and env then
    -- The deeper node is the closer one.
    local function depth(node)
      local d = 0
      while node do
        d, node = d + 1, node:parent()
      end
      return d
    end
    if depth(cmd) >= depth(env) then
      M.cmd_toggle_star()
    else
      M.env_toggle_star()
    end
  elseif cmd then
    M.cmd_toggle_star()
  elseif env then
    M.env_toggle_star()
  else
    util.warn('nothing to toggle')
  end
end

--- Toggle the trailing `\\` of the current line.
function M.cmd_toggle_break()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = line_at(row)
  local stripped = line:gsub('%s*\\\\%s*$', '')
  local new = (stripped == line) and (line:gsub('%s*$', '') .. ' \\\\') or stripped
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { new })
end

--- `\frac{a}{b}` <-> `a/b`.
---@param visual boolean|nil operate on the visual selection
function M.toggle_fraction(visual)
  local fractions = config.get('edit', 'toggle_fractions')

  if not visual then
    local node = ts.ancestor(ts.node_at_cursor(0), function(n)
      if n:type() ~= 'generic_command' then
        return false
      end
      local name = ts.command_name_node(n)
      if not name then
        return false
      end
      return vim.tbl_contains(fractions, (vim.treesitter.get_node_text(name, 0):gsub('^\\', '')))
    end)

    if node then
      local args = {}
      for child in node:iter_children() do
        if child:type():match('^curly_group') then
          args[#args + 1] = vim.treesitter.get_node_text(child, 0):sub(2, -2)
        end
      end
      if #args >= 2 then
        local sr, sc, er, ec = node:range()
        replace(sr, sc, er, ec, args[1] .. '/' .. args[2])
        return
      end
    end
  end

  -- The other direction: find `num/den` and wrap it.
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = line_at(row)
  local init = 1
  while true do
    local s, e, num, den = line:find('([%w\\%^_{}%.]+)%s*/%s*([%w\\%^_{}%.]+)', init)
    if not s then
      break
    end
    if visual or (col >= s - 1 and col <= e) then
      local replacement = ('\\%s{%s}{%s}'):format(fractions[1], num, den)
      vim.api.nvim_buf_set_text(0, row - 1, s - 1, row - 1, e, { replacement })
      return
    end
    init = e + 1
  end
  util.warn('no fraction found')
end

-- ---------------------------------------------------------------------------
-- Delimiters
-- ---------------------------------------------------------------------------

--- A uniform description of a delimiter pair.
---
--- Ranges are 0-indexed and end-exclusive, exactly like tree-sitter ranges.
--- `mod_open` / `mod_close` hold a `\left`-style modifier when there is one.
---@class NvimTexDelims
---@field open integer[]
---@field close integer[]
---@field mod_open integer[]|nil
---@field mod_close integer[]|nil

---@param node TSNode
---@return integer[]
local function node_range(node)
  local sr, sc, er, ec = node:range()
  return { sr, sc, er, ec }
end

---@param range integer[]
---@return string
local function text_of(range)
  return table.concat(vim.api.nvim_buf_get_text(0, range[1], range[2], range[3], range[4], {}), '\n')
end

---@param range integer[]
---@param text string
local function replace_range(range, text)
  replace(range[1], range[2], range[3], range[4], text)
end

--- The span covering a modifier together with its delimiter, i.e. `\left(`.
---@param mod integer[]|nil
---@param delim integer[]
---@return integer[]
local function span(mod, delim)
  if not mod then
    return delim
  end
  return { mod[1], mod[2], delim[3], delim[4] }
end

--- Text-based fallback for delimiters the parser does not group, such as the
--- plain `(a+b)` that appears all over math mode.
---@return NvimTexDelims|nil
local function delims_by_search()
  local saved = vim.api.nvim_win_get_cursor(0)
  for _, pair in ipairs({ { '(', ')' }, { '\\[', '\\]' }, { '{', '}' } }) do
    local open = vim.fn.searchpairpos(pair[1], '', pair[2], 'bcnW')
    local close = vim.fn.searchpairpos(pair[1], '', pair[2], 'cnW')
    vim.api.nvim_win_set_cursor(0, saved)
    if open[1] > 0 and close[1] > 0 then
      return {
        open = { open[1] - 1, open[2] - 1, open[1] - 1, open[2] },
        close = { close[1] - 1, close[2] - 1, close[1] - 1, close[2] },
      }
    end
  end
  return nil
end

--- The delimiter pair surrounding the cursor.
---@return NvimTexDelims|nil
local function find_delims()
  local node = ts.ancestor(ts.node_at_cursor(0), function(n)
    return ts.GROUP[n:type()] == true or n:type() == 'math_delimiter'
  end)
  if not node then
    return delims_by_search()
  end

  if node:type() == 'math_delimiter' then
    local left = node:field('left_delimiter')[1]
    local right = node:field('right_delimiter')[1]
    if not (left and right) then
      return nil
    end
    local left_cmd = node:field('left_command')[1]
    local right_cmd = node:field('right_command')[1]
    return {
      open = node_range(left),
      close = node_range(right),
      mod_open = left_cmd and node_range(left_cmd) or nil,
      mod_close = right_cmd and node_range(right_cmd) or nil,
    }
  end

  local first, last = node:child(0), node:child(node:child_count() - 1)
  if not first or not last or first:id() == last:id() then
    return nil
  end
  return { open = node_range(first), close = node_range(last) }
end

function M.delim_delete()
  local delims = find_delims()
  if not delims then
    util.warn('no surrounding delimiter')
    return
  end
  -- Closing side first, so the opening range stays valid.
  replace_range(span(delims.mod_close, delims.close), '')
  replace_range(span(delims.mod_open, delims.open), '')
end

function M.delim_change()
  local delims = find_delims()
  if not delims then
    util.warn('no surrounding delimiter')
    return
  end

  local answer = ask('Change delimiter to: ')
  if not answer then
    return
  end
  local pair = config.get('edit', 'delim_list')[answer]
  if not pair then
    util.warn(("unknown delimiter '%s'"):format(answer))
    return
  end

  -- Only the delimiter characters change; any `\left` / `\right` stays.
  replace_range(delims.close, pair[2])
  replace_range(delims.open, pair[1])
end

--- Cycle `(...)` <-> `\left(...\right)` and any further configured modifiers.
---@param reverse boolean|nil
function M.delim_toggle_modifier(reverse)
  local delims = find_delims()
  if not delims then
    util.warn('no surrounding delimiter')
    return
  end

  local cycle = { { '', '' } }
  vim.list_extend(cycle, config.get('edit', 'delim_toggle_mod_list'))

  local current = 1
  if delims.mod_open then
    local text = text_of(delims.mod_open)
    for i, mod in ipairs(cycle) do
      if mod[1] == text then
        current = i
        break
      end
    end
  end

  local step = (reverse and -1 or 1) * vim.v.count1
  local target = cycle[((current - 1 + step) % #cycle) + 1]

  local open_char = text_of(delims.open)
  local close_char = text_of(delims.close)
  replace_range(span(delims.mod_close, delims.close), target[2] .. close_char)
  replace_range(span(delims.mod_open, delims.open), target[1] .. open_char)
end

--- Add `\left` / `\right` to every delimiter inside the surrounding math zone.
function M.delim_add_modifiers()
  local scope = math_at_cursor() or ts.root(0)
  if not scope then
    return
  end

  local nodes = {}
  local function walk(node)
    -- `math_delimiter` nodes already carry a modifier.
    if ts.GROUP[node:type()] then
      nodes[#nodes + 1] = node
    end
    for child in node:iter_children() do
      if child:named() then
        walk(child)
      end
    end
  end
  walk(scope)

  local mod = config.get('edit', 'delim_toggle_mod_list')[1]
  if not mod then
    return
  end

  -- Back to front so the earlier ranges stay valid.
  for i = #nodes, 1, -1 do
    local node = nodes[i]
    local first, last = node:child(0), node:child(node:child_count() - 1)
    if first and last and first:id() ~= last:id() then
      local close = node_range(last)
      replace_range(close, mod[2] .. text_of(close))
      local open = node_range(first)
      replace_range(open, mod[1] .. text_of(open))
    end
  end
end

-- ---------------------------------------------------------------------------
-- Surrounding and creating
-- ---------------------------------------------------------------------------

--- Wrap lines `first`..`last` in an environment. Linewise, like vimtex.
---@param first integer
---@param last integer
---@param name string|nil
function M.env_surround_lines(first, last, name)
  name = name or ask('Environment: ')
  if not name then
    return
  end
  local indent = (line_at(first):match('^%s*')) or ''
  vim.api.nvim_buf_set_lines(0, last, last, false, { indent .. '\\end{' .. name .. '}' })
  vim.api.nvim_buf_set_lines(0, first - 1, first - 1, false, { indent .. '\\begin{' .. name .. '}' })
  vim.cmd(('silent normal! %dGV%dG=='):format(first, last + 2))
  vim.api.nvim_win_set_cursor(0, { math.min(first + 1, vim.api.nvim_buf_line_count(0)), 0 })
end

function M.env_surround_line()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  M.env_surround_lines(row, row)
end

function M.env_surround_visual()
  vim.cmd('normal! ' .. ESC)
  local first = vim.fn.line("'<")
  local last = vim.fn.line("'>")
  M.env_surround_lines(first, last)
end

--- Operator-pending variant, used as `operatorfunc`.
---@param _ string
function M.env_surround_operator(_)
  M.env_surround_lines(vim.fn.line("'["), vim.fn.line("']"))
end

--- Insert mode: turn the word before the cursor into a command.
function M.cmd_create_insert()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = line_at(row)
  local before = line:sub(1, col)
  local word_start = before:find('[%a@]+$')
  if not word_start then
    return
  end
  local word = before:sub(word_start)
  vim.api.nvim_buf_set_text(0, row - 1, word_start - 1, row - 1, col, { '\\' .. word .. '{' })
  vim.api.nvim_win_set_cursor(0, { row, word_start + #word + 1 })
end

--- Normal/visual mode: surround the word or selection with a command.
---@param visual boolean|nil
function M.cmd_create(visual)
  local name = ask('Command: ')
  if not name then
    return
  end
  name = name:gsub('^\\', '')

  if visual then
    vim.cmd('normal! ' .. ESC)
    local srow, scol = vim.fn.line("'<"), vim.fn.col("'<") - 1
    local erow, ecol = vim.fn.line("'>"), vim.fn.col("'>")
    vim.api.nvim_buf_set_text(0, erow - 1, ecol, erow - 1, ecol, { '}' })
    vim.api.nvim_buf_set_text(0, srow - 1, scol, srow - 1, scol, { '\\' .. name .. '{' })
  else
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = line_at(row)
    local s, e = line:find('[%w@]+', 1)
    while s and not (col >= s - 1 and col < e) do
      s, e = line:find('[%w@]+', e + 1)
    end
    if not s then
      util.warn('no word under the cursor')
      return
    end
    vim.api.nvim_buf_set_text(0, row - 1, e, row - 1, e, { '}' })
    vim.api.nvim_buf_set_text(0, row - 1, s - 1, row - 1, s - 1, { '\\' .. name .. '{' })
  end
end

--- Insert mode `]]`: close the innermost open environment or delimiter.
---
--- The parse tree of an unbalanced document is unreliable, so this walks the
--- text backwards and keeps a stack of openers instead.
function M.delim_close()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local stack = {}

  for r = 1, row do
    local line = line_at(r)
    if r == row then
      line = line:sub(1, col)
    end
    line = line:gsub('([^\\])%%.*$', '%1'):gsub('^%%.*$', '')

    local i = 1
    while i <= #line do
      local rest = line:sub(i)
      local name = rest:match('^\\begin%s*{([^}]*)}')
      if name then
        stack[#stack + 1] = { kind = 'env', name = name, indent = line_at(r):match('^%s*') }
        i = i + #rest:match('^(\\begin%s*{[^}]*})')
        goto continue
      end
      name = rest:match('^\\end%s*{([^}]*)}')
      if name then
        if #stack > 0 and stack[#stack].kind == 'env' then
          table.remove(stack)
        end
        i = i + #rest:match('^(\\end%s*{[^}]*})')
        goto continue
      end
      local left = rest:match('^\\left(.)')
      if left then
        stack[#stack + 1] = { kind = 'left', name = left }
        i = i + 6
        goto continue
      end
      if rest:match('^\\right') then
        if #stack > 0 and stack[#stack].kind == 'left' then
          table.remove(stack)
        end
        i = i + 7
        goto continue
      end
      local char = line:sub(i, i)
      if char == '\\' then
        i = i + 2
        goto continue
      elseif char == '{' or char == '[' or char == '(' then
        stack[#stack + 1] = { kind = 'char', name = char }
      elseif char == '}' or char == ']' or char == ')' then
        if #stack > 0 and stack[#stack].kind == 'char' then
          table.remove(stack)
        end
      end
      i = i + 1
      ::continue::
    end
  end

  local top = stack[#stack]
  if not top or (top.kind == 'env' and top.name == 'document') then
    return
  end

  local closers = { ['{'] = '}', ['['] = ']', ['('] = ')' }
  local matching = { ['('] = ')', ['['] = ']', ['{'] = '}', ['.'] = '.' }

  if top.kind == 'env' then
    -- `\end` goes at the cursor, on a line of its own and aligned with its
    -- `\begin`. Text before the cursor stays on the current line.
    local line = line_at(row)
    local before, after = line:sub(1, col), line:sub(col + 1)
    local closing = top.indent .. '\\end{' .. top.name .. '}'
    if before:match('^%s*$') then
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { closing .. after })
      vim.api.nvim_win_set_cursor(0, { row, #closing })
    else
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { before, closing .. after })
      vim.api.nvim_win_set_cursor(0, { row + 1, #closing })
    end
  elseif top.kind == 'left' then
    local closer = matching[top.name] or top.name
    vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { '\\right' .. closer })
    vim.api.nvim_win_set_cursor(0, { row, col + 6 + #closer })
  else
    local closer = closers[top.name]
    vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { closer })
    vim.api.nvim_win_set_cursor(0, { row, col + 1 })
  end
end

return M
