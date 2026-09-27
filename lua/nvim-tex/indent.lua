--- LaTeX-aware indentation (`indentexpr`).
---
--- The rules are VimTeX's: an environment body, a multi-line group or
--- bracket option list, `\left ... \right` and `\[ ... \]` indent their
--- contents by one level; list environments indent `\item` by one level and
--- the lines that continue an item by another; `document` does not indent at
--- all, and verbatim-like environments are left alone.
---
--- Which characters are delimiters is read off the parse tree, so a `\{`, a
--- brace in a comment or a bracket in `[a, b)` is never mistaken for one. The
--- tree is not trusted for structure while it is incomplete, though. Right
--- after `o` on `\begin{itemize}`, there is no `\end` yet and the parser
--- only has an ERROR node, which ends at the last token and so contains no
--- blank line below it. What survives in that ERROR node is the tokens. The
--- indent of a line is therefore worked out from the previous line: its
--- indent, plus the delimiters that line leaves open. Only a line that
--- starts with a closing delimiter, or with `\item`, is aligned to its opening
--- line directly, when the tree has it.
local config = require('nvim-tex.config')
local ts = require('nvim-tex.ts')

local M = {}

--- Environments whose contents are not LaTeX and keep their indentation.
local VERBATIM = vim.tbl_extend('force', ts.VERBATIM, { comment_environment = true })

local OPEN = { ['\\['] = true, ['\\('] = true }
local CLOSE = { ['\\]'] = true, ['\\)'] = true }

--- `indent.<key>` as a set, rebuilt only when the list is replaced: the
--- indent of every line asks for it.
---@type table<string, { list: string[], set: table<string, boolean> }>
local sets = {}

---@param key string
---@return table<string, boolean>
local function config_set(key)
  local list = config.get('indent', key) or {}
  local cached = sets[key]
  if not cached or cached.list ~= list then
    local out = {}
    for _, name in ipairs(list) do
      out[name] = true
    end
    cached = { list = list, set = out }
    sets[key] = cached
  end
  return cached.set
end

--- Run `fn` with `bufnr` as the current buffer. `indentexpr` already runs in
--- it, so the switch is only paid for when called from elsewhere.
---@param bufnr integer
---@param fn function
---@return any
local function in_buf(bufnr, fn)
  if bufnr == vim.api.nvim_get_current_buf() then
    return fn()
  end
  return vim.api.nvim_buf_call(bufnr, fn)
end

--- What a token does to the indentation.
---
--- Returns the kind -- `'open'`, `'close'` or `'item'` -- the number of levels
--- it is worth, and the node that spans from the opening to the closing
--- delimiter, which is where a closing line aligns to.
---@param node TSNode|nil a leaf
---@param bufnr integer
---@param opts table `{ lists = set, ignored = set }`
---@return string|nil kind, integer levels, TSNode|nil anchor
local function classify(node, bufnr, opts)
  if not node then
    return nil, 0, nil
  end
  local t = node:type()
  local parent = node:parent()
  local pt = parent and parent:type() or ''

  if t == '\\begin' or t == '\\end' then
    local kind = t == '\\begin' and 'open' or 'close'
    if pt ~= 'begin' and pt ~= 'end' then
      -- A `\end` still missing its name sits directly in an ERROR node.
      return kind, 1, nil
    end
    local name = ts.unstarred(ts.marker_name(parent, bufnr))
    local levels = 1
    if name and opts.ignored[name] then
      levels = 0
    elseif name and opts.lists[name] then
      levels = 2
    end
    return kind, levels, parent:parent()
  end

  if t == '{' or t == '}' then
    if pt:match('^curly_group') or pt == 'ERROR' then
      return t == '{' and 'open' or 'close', 1, parent
    end
  elseif t == '[' or t == ']' then
    -- Only option brackets: in text and math `[` is an ordinary character.
    if pt:match('^brack_group') then
      return t == '[' and 'open' or 'close', 1, parent
    end
  elseif t == '\\left' or t == '\\right' then
    if pt == 'math_delimiter' then
      return t == '\\left' and 'open' or 'close', 1, parent
    end
  elseif OPEN[t] then
    return 'open', 1, parent
  elseif CLOSE[t] then
    return 'close', 1, parent
  elseif t == '$$' then
    if pt == 'displayed_equation' and parent:start() ~= node:start() then
      return 'close', 1, parent
    end
    return 'open', 1, parent
  elseif t == '\\item' then
    return 'item', 1, parent
  elseif t == 'command_name' and vim.treesitter.get_node_text(node, bufnr) == '\\bibitem' then
    return 'item', 1, parent
  end
  return nil, 0, nil
end

--- The leaves of the parse tree that start on `row`, in document order.
---@param root TSNode
---@param row integer 0-indexed
---@param width integer length of the line
---@return TSNode[]
local function tokens(root, row, width)
  local out = {}
  local function walk(node)
    local sr, _, er, ec = node:range()
    if sr > row or er < row or (er == row and ec == 0 and sr < row) then
      return
    end
    if node:child_count() == 0 then
      if sr == row and not node:missing() then
        out[#out + 1] = node
      end
      return
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root:descendant_for_range(row, 0, row, width) or root)
  return out
end

--- How many levels the tokens of one line leave open, up to (not including)
--- the byte offset `stop`. Closing delimiters at the start of the line are
--- skipped: they were already taken into account for the line's own indent.
---@param list TSNode[]
---@param bufnr integer
---@param opts table
---@param stop integer|nil
---@return integer
local function open_levels(list, bufnr, opts, stop)
  local levels = 0
  local leading = true
  for index, token in ipairs(list) do
    if stop and select(3, token:start()) >= stop then
      break
    end
    local kind, n = classify(token, bufnr, opts)
    if kind == 'open' then
      levels = levels + n
    elseif kind == 'close' then
      if not leading then
        levels = levels - n
      end
    elseif kind == 'item' and index == 1 then
      levels = levels + 1
    end
    leading = leading and kind == 'close'
  end
  return levels
end

---@param bufnr integer
---@param row integer 0-indexed
---@return string
local function line_at(bufnr, row)
  return vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
end

---@param bufnr integer
---@param row integer 0-indexed
---@return integer
local function indent_of(bufnr, row)
  return in_buf(bufnr, function()
    return vim.fn.indent(row + 1)
  end)
end

--- The indent for line `lnum` of `bufnr`, or -1 to keep the current one.
---@param lnum integer 1-indexed
---@param bufnr integer|nil
---@return integer
function M.get(lnum, bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local root = ts.root(bufnr)
  if not root then
    return -1
  end

  local opts = { lists = config_set('lists'), ignored = config_set('ignored_envs') }
  local sw = in_buf(bufnr, vim.fn.shiftwidth)
  local row = lnum - 1
  local line = line_at(bufnr, row)
  local first = line:find('%S')
  local col = first and first - 1 or 0

  -- Inside a verbatim environment, the text is not ours to move.
  local node = root:descendant_for_range(row, col, row, col)
  local verbatim = ts.ancestor(node, VERBATIM)
  if verbatim then
    local srow, _, erow = verbatim:range()
    if row > srow and row < erow then
      return -1
    end
  end

  local lead
  if first then
    local own = tokens(root, row, #line)
    if own[1] and select(2, own[1]:start()) == col then
      lead = own[1]
    end
  end
  local lead_kind, lead_levels, anchor = classify(lead, bufnr, opts)

  -- A closing delimiter lines up with the line that opened it, plus what
  -- that line had already opened before: the `]` of
  -- `\begin{tikzpicture}[` belongs inside the environment.
  if lead_kind == 'close' and anchor and anchor:type() ~= 'ERROR' then
    local arow, _, abyte = anchor:start()
    if arow < row then
      local before = open_levels(tokens(root, arow, #line_at(bufnr, arow)), bufnr, opts, abyte)
      return indent_of(bufnr, arow) + math.max(0, before) * sw
    end
  end

  -- `\item` sits one level into a list environment.
  if lead_kind == 'item' then
    -- An ERROR on the way up means the list is still being typed, and the
    -- environment above it is not the one the item belongs to.
    local env = ts.ancestor(lead, function(n)
      return ts.ENVIRONMENT[n:type()] == true or n:type() == 'ERROR'
    end)
    if env and env:type() ~= 'ERROR' and env:start() < row then
      local name = ts.unstarred(ts.env_name(env, bufnr))
      return indent_of(bufnr, env:start()) + (name and opts.lists[name] and sw or 0)
    end
  end

  local prow = in_buf(bufnr, function()
    return vim.fn.prevnonblank(lnum - 1)
  end) - 1
  if prow < 0 then
    return 0
  end

  local levels = open_levels(tokens(root, prow, #line_at(bufnr, prow)), bufnr, opts)

  if lead_kind == 'close' then
    levels = levels - lead_levels
  elseif lead_kind == 'item' then
    levels = levels - 1
  end

  return math.max(0, indent_of(bufnr, prow) + levels * sw)
end

--- Entry point for `indentexpr`.
---@return integer
function M.indentexpr()
  return M.get(vim.v.lnum, vim.api.nvim_get_current_buf())
end

--- Keys that reindent the current line: the usual new-line triggers, a
--- closing delimiter, and the words that start a line on a lower level.
M.INDENTKEYS = '!^F,o,O,0},0],},],=\\item,=\\bibitem,=\\end,=\\right,=\\]'

--- Install `indentexpr` for `bufnr`.
---@param bufnr integer
function M.attach(bufnr)
  vim.bo[bufnr].indentexpr = "v:lua.require'nvim-tex.indent'.indentexpr()"
  vim.bo[bufnr].indentkeys = M.INDENTKEYS
  vim.bo[bufnr].autoindent = true
  vim.bo[bufnr].smartindent = false
  vim.bo[bufnr].cindent = false
end

return M
