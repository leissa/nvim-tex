--- LaTeX text objects, implemented on the tree-sitter parse tree.
---
---   ae/ie  environment (`\begin{...}` ... `\end{...}`, except `document`)
---   ac/ic  command
---   a$/i$  math zone
---   ad/id  delimiters (groups and `\left ... \right`)
---   am/im  `\item`
---   aP/iP  section
local ts = require('nvim-tex.ts')

local M = {}

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)

--- Select `(sr, sc)` .. `(er, ec)` (1-indexed rows, 0-indexed inclusive cols).
---@param sr integer
---@param sc integer
---@param er integer
---@param ec integer
---@param linewise boolean|nil
local function select_range(sr, sc, er, ec, linewise)
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then
    vim.cmd('normal! ' .. ESC)
  end

  local last = vim.api.nvim_buf_line_count(0)
  sr, er = math.min(sr, last), math.min(er, last)

  vim.api.nvim_win_set_cursor(0, { sr, math.max(0, sc) })
  vim.cmd('normal! ' .. (linewise and 'V' or 'v'))
  vim.api.nvim_win_set_cursor(0, { er, math.max(0, ec) })
end

---@param row integer 1-indexed
---@return string
local function line_at(row)
  return vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
end

--- Inner range of a delimited node, as 1-indexed rows / 0-indexed cols.
---@param node TSNode
---@return integer|nil, integer|nil, integer|nil, integer|nil
local function inner_of(node)
  -- For `\left( ... \right)` the inner part ends at `\right`, not at the
  -- closing delimiter character.
  local open = node:field('left_delimiter')[1] or node:child(0)
  local close = node:field('right_command')[1] or node:field('right_delimiter')[1] or node:child(node:child_count() - 1)
  if not open or not close or open:id() == close:id() then
    return nil
  end

  local _, _, osr, osc = open:range()
  local csr, csc = close:range()

  -- Step back one character from the closing delimiter.
  local er, ec = csr + 1, csc - 1
  if ec < 0 then
    er = er - 1
    ec = #line_at(er) - 1
  end
  return osr + 1, osc, er, ec
end

--- The environment surrounding the cursor, ignoring the outermost `document`.
---@return TSNode|nil
local function environment_at_cursor()
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

---@param inner boolean
function M.environment(inner)
  local node = environment_at_cursor()
  if not node then
    return
  end

  if not inner then
    local sr, sc, er, ec = ts.range(node)
    select_range(sr, sc, er, ec)
    return
  end

  local begin_node, end_node = ts.env_parts(node)
  if not (begin_node and end_node) then
    return
  end
  local _, _, ber, bec = begin_node:range()
  local esr, esc = end_node:range()

  -- `\begin` and `\end` on their own lines: select the body linewise, which
  -- is what makes `die` leave the environment markers behind.
  if esr > ber + 1 then
    select_range(ber + 2, 0, esr, #line_at(esr) - 1, true)
  else
    local er, ec = esr + 1, esc - 1
    if ec < 0 then
      er, ec = er - 1, #line_at(er - 1) - 1
    end
    select_range(ber + 1, bec, er, ec)
  end
end

---@param inner boolean
function M.command(inner)
  local bufnr = vim.api.nvim_get_current_buf()
  local node = ts.ancestor(ts.node_at_cursor(bufnr), ts.is_command)
  if not node then
    return
  end

  if not inner then
    local sr, sc, er, ec = ts.range(node)
    select_range(sr, sc, er, ec)
    return
  end

  -- Inner command is the name without the leading backslash, matching
  -- vimtex: `dic` on `\comm|and{arg}` leaves `\{arg}`.
  local name = ts.command_name_node(node)
  if not name then
    return
  end
  local sr, sc, er, ec = name:range()
  if ec == 0 then
    return
  end
  select_range(sr + 1, sc + 1, er + 1, ec - 1)
end

---@param inner boolean
function M.math(inner)
  local bufnr = vim.api.nvim_get_current_buf()
  local node = ts.ancestor(ts.node_at_cursor(bufnr), ts.MATH)
  if not node then
    return
  end

  if not inner then
    local sr, sc, er, ec = ts.range(node)
    select_range(sr, sc, er, ec)
    return
  end

  if node:type() == 'math_environment' then
    local begin_node, end_node = ts.env_parts(node)
    if not (begin_node and end_node) then
      return
    end
    local _, _, ber = begin_node:range()
    local esr = end_node:range()
    if esr > ber + 1 then
      select_range(ber + 2, 0, esr, #line_at(esr) - 1, true)
    end
    return
  end

  -- `\[` and `\]` on lines of their own: select the body linewise, the same
  -- way the environment branch above does. Going through `inner_of` would
  -- start the selection just after `\[`, which is past the end of that line.
  local open, close = node:child(0), node:child(node:child_count() - 1)
  if open and close then
    local _, _, oer, oec = open:range()
    local csr, csc = close:range()
    if csr > oer + 1 and csc == 0 and oec >= #line_at(oer + 1) then
      select_range(oer + 2, 0, csr, #line_at(csr) - 1, true)
      return
    end
  end

  local sr, sc, er, ec = inner_of(node)
  if sr then
    select_range(sr, sc, er, ec)
  end
end

--- Fallback for delimiters the parser does not group, e.g. plain `(...)`.
---@param inner boolean
---@return boolean handled
local function delimiter_fallback(inner)
  local pairs_to_try = { { '(', ')' }, { '%[', '%]' } }
  local saved = vim.api.nvim_win_get_cursor(0)

  for _, pair in ipairs(pairs_to_try) do
    local open = vim.fn.searchpairpos(pair[1], '', pair[2], 'bcnW')
    local close = vim.fn.searchpairpos(pair[1], '', pair[2], 'cnW')
    if open[1] > 0 and close[1] > 0 then
      vim.api.nvim_win_set_cursor(0, saved)
      if inner then
        local sr, sc = open[1], open[2]
        local er, ec = close[1], close[2] - 2
        if ec < 0 then
          er, ec = er - 1, #line_at(er - 1) - 1
        end
        if sr > er or (sr == er and sc > ec) then
          return true -- empty pair, nothing to select
        end
        select_range(sr, sc, er, ec)
      else
        select_range(open[1], open[2] - 1, close[1], close[2] - 1)
      end
      return true
    end
  end

  vim.api.nvim_win_set_cursor(0, saved)
  return false
end

---@param inner boolean
function M.delimiter(inner)
  local bufnr = vim.api.nvim_get_current_buf()
  local node = ts.ancestor(ts.node_at_cursor(bufnr), function(n)
    return ts.GROUP[n:type()] == true or n:type() == 'math_delimiter'
  end)

  if not node then
    delimiter_fallback(inner)
    return
  end

  if not inner then
    local sr, sc, er, ec = ts.range(node)
    select_range(sr, sc, er, ec)
    return
  end

  local sr, sc, er, ec = inner_of(node)
  if sr and not (sr > er or (sr == er and sc > ec)) then
    select_range(sr, sc, er, ec)
  end
end

---@param inner boolean
function M.item(inner)
  local bufnr = vim.api.nvim_get_current_buf()
  local node = ts.ancestor(ts.node_at_cursor(bufnr), ts.ITEM)
  if not node then
    return
  end

  local sr, sc, er, ec = ts.range(node)
  if not inner then
    local before = line_at(sr):sub(1, sc)
    local after = line_at(er):sub(ec + 2)
    -- A whole-line item is removed linewise, so `dam` takes the line with it.
    if before:match('^%s*$') and after:match('^%s*$') then
      select_range(sr, 0, er, math.max(0, #line_at(er) - 1), true)
    else
      select_range(sr, sc, er, ec)
    end
    return
  end

  -- Inner item: everything after the `\item` token (and its optional `[...]`).
  local first = node:named_child(0)
  if not first then
    return
  end
  local isr, isc = first:range()
  select_range(isr + 1, isc, er, ec)
end

---@param inner boolean
function M.section(inner)
  local bufnr = vim.api.nvim_get_current_buf()
  local node = ts.ancestor(ts.node_at_cursor(bufnr), ts.SECTION)
  if not node then
    return
  end

  local sr, _, er, _ = ts.range(node)
  if not inner then
    select_range(sr, 0, er, math.max(0, #line_at(er) - 1), true)
    return
  end

  -- Drop the heading itself: start after the line holding the last part of
  -- the sectioning command's title group.
  local heading_end = sr
  local title = node:named_child(0)
  if title then
    local _, _, ter = title:range()
    heading_end = ter + 1
  end
  if er > heading_end then
    select_range(heading_end + 1, 0, er, math.max(0, #line_at(er) - 1), true)
  end
end

--- Mapping table: lhs -> function. Used by `nvim-tex.keymaps`.
M.map = {
  ['ae'] = function()
    M.environment(false)
  end,
  ['ie'] = function()
    M.environment(true)
  end,
  ['ac'] = function()
    M.command(false)
  end,
  ['ic'] = function()
    M.command(true)
  end,
  ['a$'] = function()
    M.math(false)
  end,
  ['i$'] = function()
    M.math(true)
  end,
  ['ad'] = function()
    M.delimiter(false)
  end,
  ['id'] = function()
    M.delimiter(true)
  end,
  ['am'] = function()
    M.item(false)
  end,
  ['im'] = function()
    M.item(true)
  end,
  ['aP'] = function()
    M.section(false)
  end,
  ['iP'] = function()
    M.section(true)
  end,
}

return M
