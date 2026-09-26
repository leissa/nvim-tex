--- Tree-sitter helpers.
---
--- Everything structural in this plugin -- motions, text objects, the table of
--- contents, the ds/cs/ts edits -- is driven from the `latex` parse tree
--- rather than from regular expressions or syntax groups.
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = {}

--- `\begin{...} ... \end{...}` blocks.
M.ENVIRONMENT = {
  generic_environment = true,
  math_environment = true,
}

--- Sectioning commands, from coarse to fine. The parser nests them, so a
--- `subsection` node is a child of its `section` node.
M.SECTION = {
  part = true,
  chapter = true,
  section = true,
  subsection = true,
  subsubsection = true,
  paragraph = true,
  subparagraph = true,
}

--- Math zones of any flavour.
M.MATH = {
  inline_formula = true,
  displayed_equation = true,
  math_environment = true,
}

--- Environments that open a math zone. The parse tree already knows this for
--- every environment whose `\end` is there; the list is only needed while one
--- is still being typed (see `M.in_math`).
M.MATH_ENVIRONMENT_NAMES = {
  align = true,
  alignat = true,
  aligned = true,
  alignedat = true,
  array = true,
  bmatrix = true,
  Bmatrix = true,
  cases = true,
  displaymath = true,
  eqnarray = true,
  equation = true,
  flalign = true,
  gather = true,
  gathered = true,
  math = true,
  matrix = true,
  multline = true,
  pmatrix = true,
  smallmatrix = true,
  split = true,
  vmatrix = true,
  Vmatrix = true,
  xalignat = true,
  xxalignat = true,
}

--- Groups that can act as delimiters for `ad`/`id`.
M.GROUP = {
  curly_group = true,
  curly_group_text = true,
  curly_group_path = true,
  curly_group_path_list = true,
  curly_group_label = true,
  curly_group_label_list = true,
  curly_group_command_name = true,
  curly_group_key_value = true,
  curly_group_text_list = true,
  brack_group = true,
  brack_group_text = true,
  brack_group_argc = true,
  brack_group_key_value = true,
  mixed_group = true,
}

M.COMMENT = { line_comment = true, comment_environment = true }

M.ITEM = { enum_item = true }

local warned = {}

--- Get the LaTeX parser for `bufnr`, or nil when it is unavailable.
---@param bufnr integer|nil
---@return vim.treesitter.LanguageTree|nil
function M.parser(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not config.get('treesitter', 'enabled') then
    return nil
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'latex')
  if not ok or not parser then
    if config.get('treesitter', 'warn_missing_parser') and not warned[bufnr] then
      warned[bufnr] = true
      util.warn("the 'latex' tree-sitter parser is not available; run :TSInstall latex")
    end
    return nil
  end
  return parser
end

---@param bufnr integer|nil
---@return TSNode|nil
function M.root(bufnr)
  local parser = M.parser(bufnr)
  if not parser then
    return nil
  end
  local trees = parser:parse()
  return trees and trees[1] and trees[1]:root() or nil
end

--- The smallest named node covering the cursor.
---
--- `vim.treesitter.get_node` needs an already parsed tree, which is not
--- guaranteed right after a buffer is created, so the root is fetched (and
--- thereby parsed) explicitly here.
---@param bufnr integer|nil
---@param pos integer[]|nil `{ row (1-indexed), col (0-indexed) }`
---@return TSNode|nil
function M.node_at_cursor(bufnr, pos)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local root = M.root(bufnr)
  if not root then
    return nil
  end

  pos = pos or vim.api.nvim_win_get_cursor(0)
  local row = math.max(0, pos[1] - 1)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local col = math.max(0, math.min(pos[2], math.max(0, #line - 1)))

  return root:named_descendant_for_range(row, col, row, col)
end

--- Walk up from `node` to the first ancestor (inclusive) matching `types`.
---@param node TSNode|nil
---@param types table<string, boolean>|fun(node: TSNode): boolean
---@param predicate fun(node: TSNode): boolean|nil extra filter
---@return TSNode|nil
function M.ancestor(node, types, predicate)
  local matches = type(types) == 'function' and types or function(n)
    return types[n:type()] == true
  end
  while node do
    if matches(node) and (not predicate or predicate(node)) then
      return node
    end
    node = node:parent()
  end
  return nil
end

--- Collect every node matching `types`, in document order.
---@param bufnr integer|nil
---@param types table<string, boolean>|fun(node: TSNode): boolean
---@return TSNode[]
function M.collect(bufnr, types)
  local root = M.root(bufnr)
  if not root then
    return {}
  end
  local matches = type(types) == 'function' and types or function(n)
    return types[n:type()] == true
  end

  local out = {}
  local function walk(node)
    if matches(node) then
      out[#out + 1] = node
    end
    for child in node:iter_children() do
      if child:named() then
        walk(child)
      end
    end
  end
  walk(root)
  return out
end

--- The `begin`/`end` children of an environment node.
---@param node TSNode
---@return TSNode|nil begin_node, TSNode|nil end_node
function M.env_parts(node)
  local begin_node, end_node
  for child in node:iter_children() do
    local t = child:type()
    if t == 'begin' then
      begin_node = child
    elseif t == 'end' then
      end_node = child
    end
  end
  return begin_node, end_node
end

--- The name of an environment, e.g. `itemize` for `\begin{itemize}`.
---@param node TSNode|nil
---@param bufnr integer|nil
---@return string|nil
function M.env_name(node, bufnr)
  if not node or not M.ENVIRONMENT[node:type()] then
    return nil
  end
  local begin_node = M.env_parts(node)
  if not begin_node then
    return nil
  end
  for child in begin_node:iter_children() do
    if child:type():match('^curly_group_text') then
      return vim.trim(vim.treesitter.get_node_text(child, bufnr or 0):gsub('[{}]', ''))
    end
  end
  return nil
end

--- Is this node a LaTeX command (but not a sectioning command)?
---@param node TSNode
---@return boolean
function M.is_command(node)
  local t = node:type()
  if M.SECTION[t] then
    return false
  end
  if t == 'generic_command' then
    return true
  end
  return t:match('_include$') ~= nil
    or t:match('_definition$') ~= nil
    or t:match('_reference$') ~= nil
    or t:match('_declaration$') ~= nil
    or t == 'citation'
    or t == 'caption'
end

--- The `command_name` child of a command node, if any.
---@param node TSNode
---@return TSNode|nil
function M.command_name_node(node)
  for child in node:iter_children() do
    if child:type() == 'command_name' then
      return child
    end
    if not child:named() then
      -- Specialised commands keep the literal `\section` as an anonymous leaf.
      return child
    end
  end
  return nil
end

--- Node range as 1-indexed, end-inclusive `(srow, scol, erow, ecol)`, which is
--- what `nvim_win_set_cursor` and visual selections want.
---@param node TSNode
---@return integer, integer, integer, integer
function M.range(node)
  local sr, sc, er, ec = node:range()
  if ec == 0 and er > sr then
    -- The node ends at column 0 of the following line; clamp to the end of
    -- the previous line so the selection does not swallow a line break.
    er = er - 1
    local line = vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1] or ''
    ec = #line
  end
  return sr + 1, sc, er + 1, math.max(0, ec - 1)
end

--- Is the cursor (1-indexed row, 0-indexed col) inside `node`?
---@param node TSNode
---@param row integer
---@param col integer
---@return boolean
function M.contains(node, row, col)
  local sr, sc, er, ec = node:range()
  local r = row - 1
  if r < sr or r > er then
    return false
  end
  if r == sr and col < sc then
    return false
  end
  if r == er and col > ec then
    return false
  end
  return true
end

--- How far back `in_math` scans when there is no parse tree to lean on.
local SCAN_LIMIT = 200

--- Walk the text between two positions and decide whether it ends in math.
---
--- This is the hand written fallback for regions the parser could not make
--- sense of, so it stays deliberately simple: dollars toggle, `\(` and `\[`
--- open, `\)` and `\]` close, and a math environment does the same.
---@param bufnr integer
---@param srow integer 0-indexed
---@param scol integer
---@param erow integer 0-indexed
---@param ecol integer
---@return boolean
local function scan_math(bufnr, srow, scol, erow, ecol)
  local ok, chunks = pcall(vim.api.nvim_buf_get_text, bufnr, srow, scol, erow, ecol, {})
  if not ok then
    return false
  end
  local text = table.concat(chunks, '\n')

  local math = false
  local i = 1
  while i <= #text do
    local char = text:sub(i, i)
    if char == '%' then
      local nl = text:find('\n', i, true)
      i = nl and nl + 1 or #text + 1
    elseif char == '$' then
      math = not math
      i = i + (text:sub(i, i + 1) == '$$' and 2 or 1)
    elseif char == '\\' then
      local pair = text:sub(i, i + 1)
      local begin_cmd, opened = text:match('^(\\begin%s*{([^}]*)})', i)
      local end_cmd, closed = text:match('^(\\end%s*{([^}]*)})', i)
      if pair == '\\(' or pair == '\\[' then
        math = true
        i = i + 2
      elseif pair == '\\)' or pair == '\\]' then
        math = false
        i = i + 2
      elseif begin_cmd then
        math = math or M.MATH_ENVIRONMENT_NAMES[(opened:gsub('%*$', ''))] == true
        i = i + #begin_cmd
      elseif end_cmd then
        math = math and not M.MATH_ENVIRONMENT_NAMES[(closed:gsub('%*$', ''))]
        i = i + #end_cmd
      else
        -- An escaped character, `\$` among them.
        i = i + 2
      end
    else
      i = i + 1
    end
  end
  return math
end

--- The first row of the paragraph `row` (0-indexed) belongs to.
---@param bufnr integer
---@param row integer
---@return integer
local function paragraph_start(bufnr, row)
  local limit = math.max(0, row - SCAN_LIMIT)
  for r = row, limit, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, r, r + 1, false)[1]
    if line == nil or line:match('^%s*$') then
      return math.min(r + 1, row)
    end
  end
  return limit
end

--- Is the position inside a math zone?
---
--- Answered from the parse tree, which copes with a formula whose closing
--- delimiter is not typed yet: the parser inserts a MISSING node and the math
--- node is there all the same. What it cannot parse at all -- an empty `$$`,
--- an environment before its `\end` exists -- shows up as an ERROR node, and
--- only that region is then scanned by hand.
---@param bufnr integer|nil
---@param pos integer[]|nil `{ row (1-indexed), col (0-indexed) }`
---@return boolean
function M.in_math(bufnr, pos)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  pos = pos or vim.api.nvim_win_get_cursor(0)

  local row = math.max(0, pos[1] - 1)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local col = math.max(0, math.min(pos[2], #line))

  local node = M.node_at_cursor(bufnr, pos)
  if node then
    if M.ancestor(node, M.MATH) then
      return true
    end
    local err = M.ancestor(node, function(n)
      return n:type() == 'ERROR'
    end)
    if not err then
      return false
    end
    local srow, scol = err:range()
    return scan_math(bufnr, srow, scol, row, col)
  end

  -- No parser at all. Inline math cannot span a blank line, so the paragraph
  -- is a safe place to start counting.
  return scan_math(bufnr, paragraph_start(bufnr, row), 0, row, col)
end

return M
