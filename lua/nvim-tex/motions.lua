--- Tree-sitter driven motions.
---
--- All motions are exclusive and work in normal, visual and operator-pending
--- mode. They accept a count.
local ts = require('nvim-tex.ts')

local M = {}

---@param node TSNode
---@return integer, integer 1-indexed row, 0-indexed col
local function node_start(node)
  local sr, sc = node:range()
  return sr + 1, sc
end

---@param node TSNode
---@return integer, integer
local function node_end(node)
  local _, _, er, ec = node:range()
  if ec == 0 and er > 0 then
    er = er - 1
    ec = #(vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1] or '')
  end
  return er + 1, math.max(0, ec - 1)
end

--- Collect the jump targets for `kind`.
---@param kind string
---@param which 'start'|'finish'
---@return table[] list of `{ row, col }`, sorted
local function targets(kind, which)
  local bufnr = vim.api.nvim_get_current_buf()
  local nodes

  if kind == 'section' then
    nodes = ts.collect(bufnr, ts.SECTION)
  elseif kind == 'environment' then
    nodes = ts.collect(bufnr, ts.ENVIRONMENT)
  elseif kind == 'math' then
    nodes = ts.collect(bufnr, ts.MATH)
  elseif kind == 'frame' then
    nodes = ts.collect(bufnr, function(node)
      return ts.ENVIRONMENT[node:type()] and ts.env_name(node, bufnr) == 'frame'
    end)
  elseif kind == 'comment' then
    nodes = ts.collect(bufnr, ts.COMMENT)
  else
    nodes = {}
  end

  local out = {}
  for _, node in ipairs(nodes) do
    local row, col
    if which == 'start' then
      -- For environments and display math the interesting position is the
      -- `\begin` / opening delimiter, which is exactly the node start.
      row, col = node_start(node)
    else
      local _, end_node = ts.env_parts(node)
      if end_node then
        row, col = node_start(end_node)
      else
        row, col = node_end(node)
      end
    end
    out[#out + 1] = { row, col }
  end

  table.sort(out, function(a, b)
    if a[1] ~= b[1] then
      return a[1] < b[1]
    end
    return a[2] < b[2]
  end)
  return out
end

---@param a table
---@param row integer
---@param col integer
---@return boolean
local function after(a, row, col)
  return a[1] > row or (a[1] == row and a[2] > col)
end

---@param kind string
---@param which 'start'|'finish'
---@param direction 'next'|'prev'
function M.jump(kind, which, direction)
  local count = vim.v.count1
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1], cursor[2]
  local list = targets(kind, which)
  if #list == 0 then
    return
  end

  local found
  if direction == 'next' then
    local seen = 0
    for _, pos in ipairs(list) do
      if after(pos, row, col) then
        seen = seen + 1
        if seen == count then
          found = pos
          break
        end
      end
    end
  else
    local seen = 0
    for i = #list, 1, -1 do
      local pos = list[i]
      if not after(pos, row, col) and not (pos[1] == row and pos[2] == col) then
        seen = seen + 1
        if seen == count then
          found = pos
          break
        end
      end
    end
  end

  if found then
    vim.api.nvim_win_set_cursor(0, { found[1], found[2] })
  end
end

--- `%`: jump between `\begin` and the matching `\end`, or between the
--- delimiters of a math zone. Falls back to the built-in `%`.
function M.match_pair()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1], cursor[2]

  local node = ts.node_at_cursor(bufnr)
  local env = ts.ancestor(node, ts.ENVIRONMENT)
  if env then
    local begin_node, end_node = ts.env_parts(env)
    if begin_node and end_node then
      local on_begin = ts.contains(begin_node, row, col)
      local target = on_begin and end_node or begin_node
      -- Only jump when the cursor sits on one of the two markers; otherwise
      -- `%` inside the body should behave normally.
      if on_begin or ts.contains(end_node, row, col) then
        local sr, sc = node_start(target)
        vim.api.nvim_win_set_cursor(0, { sr, sc })
        return
      end
    end
  end

  local math = ts.ancestor(node, ts.MATH)
  if math and math:type() ~= 'math_environment' then
    local sr, sc = node_start(math)
    local er, ec = node_end(math)
    if row == sr and col <= sc + 1 then
      vim.api.nvim_win_set_cursor(0, { er, ec })
      return
    elseif row == er and col >= ec - 1 then
      vim.api.nvim_win_set_cursor(0, { sr, sc })
      return
    end
  end

  vim.cmd('normal! %')
end

--- Mapping table: lhs -> function. Used by `nvim-tex.keymaps`.
M.map = {
  [']]'] = function()
    M.jump('section', 'start', 'next')
  end,
  ['[['] = function()
    M.jump('section', 'start', 'prev')
  end,
  [']['] = function()
    M.jump('section', 'finish', 'next')
  end,
  ['[]'] = function()
    M.jump('section', 'finish', 'prev')
  end,
  [']m'] = function()
    M.jump('environment', 'start', 'next')
  end,
  ['[m'] = function()
    M.jump('environment', 'start', 'prev')
  end,
  [']M'] = function()
    M.jump('environment', 'finish', 'next')
  end,
  ['[M'] = function()
    M.jump('environment', 'finish', 'prev')
  end,
  [']n'] = function()
    M.jump('math', 'start', 'next')
  end,
  ['[n'] = function()
    M.jump('math', 'start', 'prev')
  end,
  [']N'] = function()
    M.jump('math', 'finish', 'next')
  end,
  ['[N'] = function()
    M.jump('math', 'finish', 'prev')
  end,
  [']r'] = function()
    M.jump('frame', 'start', 'next')
  end,
  ['[r'] = function()
    M.jump('frame', 'start', 'prev')
  end,
  [']R'] = function()
    M.jump('frame', 'finish', 'next')
  end,
  ['[R'] = function()
    M.jump('frame', 'finish', 'prev')
  end,
  [']/'] = function()
    M.jump('comment', 'start', 'next')
  end,
  ['[/'] = function()
    M.jump('comment', 'start', 'prev')
  end,
  [']*'] = function()
    M.jump('comment', 'finish', 'next')
  end,
  ['[*'] = function()
    M.jump('comment', 'finish', 'prev')
  end,
  ['%'] = M.match_pair,
}

return M
