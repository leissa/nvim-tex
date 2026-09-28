--- Node names in a TikZ picture: where a name is defined, where it is used,
--- renaming it, and completing node and style names.
---
--- A node is named by `\node (a)`, `node (a)` on a path, `\coordinate (a)`,
--- `\matrix (m)` or a `name=a` option. The `(a)` may come before or after the
--- node's options and its `at (x,y)`. A name is used as a coordinate `(a)` or
--- `(a.north)` -- in calc expressions `($(a)!0.5!(b)$)` and `fit=(a) (b)`
--- too -- and by the positioning library as `right=of a`. Comments are
--- ignored; the parser has already told them apart.
---
--- Names belong to the picture they are defined in.
local config = require('nvim-tex.config')
local tikz = require('nvim-tex.tikz')
local ts = require('nvim-tex.ts')
local util = require('nvim-tex.util')

local M = {}

---@class nvim-tex.TikzName
---@field name string
---@field range integer[] `{ srow, scol, erow, ecol }`, 0-indexed, end exclusive

--- Keywords followed by the name of what they make.
local NAMED = { node = true, coordinate = true, matrix = true }

--- The text of `picture` with its comments blanked out, and a function
--- turning a byte offset into it (1-indexed) into a buffer position.
---@param picture TSNode
---@param bufnr integer
---@return string text, fun(offset: integer): integer, integer
local function picture_text(picture, bufnr)
  local sr, sc, er, ec = picture:range()
  local lines = vim.api.nvim_buf_get_text(bufnr, sr, sc, er, ec, {})

  local function blank(node)
    local csr, csc, cer, cec = node:range()
    for row = csr, cer do
      local i = row - sr + 1
      local line = lines[i]
      local shift = row == sr and sc or 0
      local from = (row == csr and csc or 0) - shift + 1
      local to = (row == cer and cec or #line + shift) - shift
      lines[i] = line:sub(1, from - 1) .. string.rep(' ', to - from + 1) .. line:sub(to + 1)
    end
  end
  local function walk(node)
    for child in node:iter_children() do
      if ts.COMMENT[child:type()] then
        blank(child)
      elseif child:child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(picture)

  local starts = {}
  local offset = 1
  for i, line in ipairs(lines) do
    starts[i] = offset
    offset = offset + #line + 1
  end
  local function position(at)
    local i = #starts
    while i > 1 and starts[i] > at do
      i = i - 1
    end
    return sr + i - 1, at - starts[i] + (i == 1 and sc or 0)
  end
  return table.concat(lines, '\n'), position
end

---@param position fun(offset: integer): integer, integer
---@param name string
---@param from integer offset of the name's first byte
---@return nvim-tex.TikzName
local function entry(position, name, from)
  local srow, scol = position(from)
  local erow, ecol = position(from + #name)
  return { name = name, range = { srow, scol, erow, ecol } }
end

--- Where `picture` names its nodes, in document order.
---@param picture TSNode
---@param bufnr integer
---@return nvim-tex.TikzName[]
function M.definitions(picture, bufnr)
  local text, position = picture_text(picture, bufnr)
  local out = {}

  for word, i in text:gmatch('(%a+)()') do
    -- `node [draw] (a) at (0,0)`, `node at (0,0) (a)`: skip the options and
    -- the position until the name, or whatever else ends the search.
    while NAMED[word] do
      i = text:match('^%s*()', i)
      if text:sub(i, i) == '[' then
        i = text:match('^%b[]()', i)
      elseif text:match('^at%f[^%a]', i) then
        i = text:match('^at%s*%b()()', i)
      elseif text:sub(i, i) == '(' then
        local inner, from = text:match('^%((%s*)[^()]-%)()', i)
        local name = vim.trim(text:match('^%(([^()]-)%)', i) or '')
        if name ~= '' and not name:find('[,:$]') then
          out[#out + 1] = entry(position, name, i + 1 + #inner)
        end
        i = from
        break
      else
        break
      end
      if not i then
        break
      end
    end
  end

  -- `[name=a]`
  for from, name in text:gmatch('[%[,]%s*name%s*=%s*()([^,%]]*)') do
    name = vim.trim(name)
    if name ~= '' then
      out[#out + 1] = entry(position, name, from)
    end
  end

  table.sort(out, function(a, b)
    return a.range[1] < b.range[1] or (a.range[1] == b.range[1] and a.range[2] < b.range[2])
  end)
  return out
end

--- Every place in `picture` that defines or uses the node `name`.
---@param picture TSNode
---@param bufnr integer
---@param name string
---@return nvim-tex.TikzName[]
function M.occurrences(picture, bufnr, name)
  local text, position = picture_text(picture, bufnr)
  local out = {}
  local init = 1
  while true do
    local s, e = text:find(name, init, true)
    if not s then
      break
    end
    init = e + 1
    local before = text:sub(math.max(1, s - 40), s - 1)
    local after = text:sub(e + 1, e + 1)
    local coordinate = before:match('%(%s*$') and (after == '.' or text:match('^%s*%)', e + 1))
    local keyword = (before:match('%f[%a]of%s+$') or before:match('[%[,]%s*name%s*=%s*$')) and not after:match('[%w_]')
    if coordinate or keyword then
      out[#out + 1] = entry(position, name, s)
    end
  end
  return out
end

---@param range integer[]
---@param row integer
---@param col integer
---@return boolean
local function covers(range, row, col)
  return (row > range[1] or (row == range[1] and col >= range[2]))
    and (row < range[3] or (row == range[3] and col < range[4]))
end

--- The node name at a position, with its picture and every occurrence.
---@param bufnr integer|nil
---@param row integer 0-indexed
---@param col integer 0-indexed
---@return string|nil name, TSNode|nil picture, nvim-tex.TikzName[]|nil occurrences
function M.name_at(bufnr, row, col)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local picture = tikz.picture(ts.node_at_cursor(bufnr, { row + 1, col }), bufnr)
  if not picture then
    return nil
  end
  local seen = {}
  for _, definition in ipairs(M.definitions(picture, bufnr)) do
    if not seen[definition.name] then
      seen[definition.name] = true
      local occurrences = M.occurrences(picture, bufnr, definition.name)
      for _, occurrence in ipairs(occurrences) do
        if covers(occurrence.range, row, col) then
          return definition.name, picture, occurrences
        end
      end
    end
  end
  return nil
end

--- Jump to where the node under the cursor is defined.
---@return boolean found a node name under the cursor
function M.goto_definition()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local name, picture = M.name_at(bufnr, cursor[1] - 1, cursor[2])
  if not name then
    return false
  end
  for _, definition in ipairs(M.definitions(picture, bufnr)) do
    if definition.name == name then
      vim.cmd("normal! m'")
      vim.api.nvim_win_set_cursor(0, { definition.range[1] + 1, definition.range[2] })
      return true
    end
  end
  return true
end

--- Rename the node under the cursor throughout its picture. Without `new`,
--- ask for the name.
---@param new string|nil
function M.rename(new)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local name, _, occurrences = M.name_at(bufnr, cursor[1] - 1, cursor[2])
  if not name then
    util.warn('no TikZ node name under the cursor')
    return
  end

  local function apply(to)
    if not to or to == '' or to == name then
      return
    end
    -- From the end, so the earlier positions stay valid.
    for i = #occurrences, 1, -1 do
      local r = occurrences[i].range
      vim.api.nvim_buf_set_text(bufnr, r[1], r[2], r[3], r[4], { to })
    end
    util.info(('renamed %s to %s in %d places'):format(name, to, #occurrences))
  end

  if new then
    apply(new)
  else
    vim.ui.input({ prompt = ('Rename node %s to: '):format(name), default = name }, apply)
  end
end

--- Style names defined in `lines`: `name/.style=...`, `name/.append
--- style=...` and `\tikzstyle{name}`.
---@param lines string[]
---@param out table<string, boolean>
local function styles_in(lines, out)
  local text = table.concat(lines, '\n')
  for name in text:gmatch('([%w%s_%-]+)/%.%a*%s*style') do
    out[vim.trim(name)] = true
  end
  for name in text:gmatch('\\tikzstyle%s*{([^}]+)}') do
    out[vim.trim(name)] = true
  end
end

--- The style names of the buffer and the main file.
---@param bufnr integer
---@return string[]
function M.styles(bufnr)
  local found = {}
  styles_in(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), found)
  local ok, project = pcall(require('nvim-tex.project').get, bufnr)
  if ok and project and util.normalize(project.main) ~= util.normalize(vim.api.nvim_buf_get_name(bufnr)) then
    local main = vim.fn.bufnr(project.main)
    local lines = (main ~= -1 and vim.api.nvim_buf_is_loaded(main)) and vim.api.nvim_buf_get_lines(main, 0, -1, false)
      or util.readlines(project.main)
    styles_in(lines, found)
  end
  found[''] = nil
  local out = vim.tbl_keys(found)
  table.sort(out)
  return out
end

--- 'completefunc': node names of the picture at the cursor and style names.
---@param findstart integer
---@param base string
---@return integer|table[]
function M.complete(findstart, base)
  local cursor = vim.api.nvim_win_get_cursor(0)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line():sub(1, cursor[2])
    return (line:find('[%w_%-]*$') or cursor[2] + 1) - 1
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local items, seen = {}, {}
  local function add(word, kind)
    if not seen[word] and vim.startswith(word, base) then
      seen[word] = true
      items[#items + 1] = { word = word, kind = kind, menu = '[tikz]' }
    end
  end
  local picture = tikz.picture(ts.node_at_cursor(bufnr), bufnr)
  if picture then
    for _, definition in ipairs(M.definitions(picture, bufnr)) do
      add(definition.name, 'node')
    end
  end
  for _, style in ipairs(M.styles(bufnr)) do
    add(style, 'style')
  end
  return items
end

--- Set 'completefunc' for `bufnr`, unless something else already has.
---@param bufnr integer
function M.attach(bufnr)
  if config.get('tikz', 'completefunc') and vim.bo[bufnr].completefunc == '' then
    vim.bo[bufnr].completefunc = "v:lua.require'nvim-tex.tikz.nodes'.complete"
  end
end

return M
