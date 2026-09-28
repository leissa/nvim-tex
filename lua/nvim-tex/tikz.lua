--- The statements of a TikZ picture.
---
--- The parser has no TikZ grammar: the body of a `tikzpicture` is a flat run
--- of words, commands, groups and bracket tokens. That is enough to find the
--- statements a picture is made of. Groups, math, comments and commands come
--- from the tree, so a `;` in a node label `{$x;y$}` or in a comment never ends
--- a statement. What is left is the `;` in the words between them, and the
--- `[`/`]` and `(`/`)` tokens, which the parser leaves unpaired.
---
--- A statement is one of
---
---   - a path: from a command in `tikz.path_commands`, or anything that is not
---     a command, up to the `;` that ends it;
---   - a `\foreach` loop: up to the `;` of the path it repeats, or to the end
---     of its `{ ... }` body, whose statements are statements in turn;
---   - any other command, with the braced arguments that follow it on the same
---     line: `\tikzset{...}`, `\pgfmathsetmacro{\x}{1}`, `\def\x{1}`.
---
--- An environment in a picture (`scope`, `pgfonlayer`, `axis`) and a `{ ... }`
--- scope are lists of statements of their own.
local config = require('nvim-tex.config')
local ts = require('nvim-tex.ts')

local M = {}

---@class nvim-tex.TikzStatement
---@field range integer[] `{ srow, scol, erow, ecol }`, 0-indexed, end exclusive
---@field reach integer[] `{ row, col }` the statement covers up to: the end of
---   `range`, or for a path whose `;` is missing, the end of its region
---@field kind 'path'|'foreach'|'command'
---@field semicolon boolean ended by a `;`, the last character of `range`
---@field region TSNode the environment or `{ ... }` group it is part of

--- Nodes whose children belong to the same run of tokens.
local TRANSPARENT = { text = true, ERROR = true }

--- `tikz.<key>` as a set, rebuilt only when the list is replaced.
---@type table<string, { list: string[], set: table<string, boolean> }>
local sets = {}

---@param key string
---@return table<string, boolean>
local function config_set(key)
  local list = config.get('tikz', key) or {}
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

--- Is `node` a picture, an environment named in `tikz.environments`?
---@param node TSNode
---@param bufnr integer
---@return boolean
function M.is_picture(node, bufnr)
  return node:type() == 'generic_environment' and config_set('environments')[ts.env_name(node, bufnr) or ''] == true
end

--- The innermost picture around `node`.
---@param node TSNode|nil
---@param bufnr integer
---@return TSNode|nil
function M.picture(node, bufnr)
  return ts.ancestor(node, function(n)
    return M.is_picture(n, bufnr)
  end)
end

--- The name of a command node without its backslash, e.g. `draw`.
---@param node TSNode|nil
---@param bufnr integer
---@return string|nil
local function command_name(node, bufnr)
  if not node or node:type() ~= 'generic_command' then
    return nil
  end
  local name = ts.child_of_type(node, 'command_name')
  return name and vim.treesitter.get_node_text(name, bufnr):sub(2)
end

---@class nvim-tex.TikzToken
---@field type string node type, or `;`
---@field node? TSNode
---@field text? string the text of a word
---@field range integer[] 0-indexed, end exclusive

--- The tokens of a region: the children of an environment between `\begin`
--- and `\end`, or of a group between its braces, with `text` and ERROR nodes
--- opened up and words split at their `;`.
---@param region TSNode
---@param bufnr integer
---@return nvim-tex.TikzToken[]
local function tokens(region, bufnr)
  local out = {}
  local function word(node)
    local text = vim.treesitter.get_node_text(node, bufnr)
    local row, col = node:start()
    local from = 1
    while from <= #text do
      local semi = text:find(';', from, true)
      local stop = semi and semi - 1 or #text
      if stop >= from then
        out[#out + 1] = {
          type = 'word',
          node = node,
          text = text:sub(from, stop),
          range = { row, col + from - 1, row, col + stop },
        }
      end
      if semi then
        out[#out + 1] = { type = ';', range = { row, col + semi - 1, row, col + semi } }
      end
      from = (semi or #text) + 1
    end
  end
  local function add(node, top)
    for child in node:iter_children() do
      local t = child:type()
      if TRANSPARENT[t] then
        add(child, false)
      elseif t == 'word' then
        word(child)
      elseif child:missing() or t == 'begin' or t == 'end' or (top and (t == '{' or t == '}')) then
        -- Not part of the body.
      else
        out[#out + 1] = { type = t, node = child, range = { child:range() } }
      end
    end
  end
  add(region, true)
  return out
end

--- Where the body of a region ends: at its `\end` or closing brace.
---@param region TSNode
---@return integer[] `{ row, col }`
local function body_end(region)
  local last = region:child(region:child_count() - 1)
  if last and (last:type() == 'end' or last:type() == '}') then
    return { last:start() }
  end
  local _, _, er, ec = region:range()
  return { er, ec }
end

local COMMENT = { line_comment = true, comment_environment = true }

--- Does a node at the start of a statement make it a command statement?
---@param token nvim-tex.TikzToken
---@return boolean
local function command_like(token)
  return token.node ~= nil and (ts.is_command(token.node) or token.type:match('_import$') ~= nil)
end

--- Read the statements of `region` into `out`, in document order.
---@param region TSNode
---@param bufnr integer
---@param out nvim-tex.TikzStatement[]
local function scan(region, bufnr, out)
  local paths = config_set('path_commands')
  local current ---@type nvim-tex.TikzStatement|table|nil
  local last ---@type nvim-tex.TikzStatement|table|nil the statement before, at this level
  local depth = 0 -- `[` and `(` tokens the path leaves open

  local function start(token, kind)
    current = { range = { unpack(token.range) }, kind = kind, semicolon = false, region = region }
    out[#out + 1] = current
    depth = 0
  end

  local function extend(token)
    current.range[3], current.range[4] = token.range[3], token.range[4]
  end

  local function finish()
    current.reach = { current.range[3], current.range[4] }
    last, current = current, nil
  end

  --- A region of its own inside this one.
  local function nested(node)
    if not M.is_picture(node, bufnr) then
      scan(node, bufnr, out)
    end
  end

  --- Take `token` into the statement being read, or start one with it.
  --- Returns false when the statement ended before `token`, which is then
  --- taken again.
  ---@param token nvim-tex.TikzToken
  ---@return boolean
  local function step(token)
    local t = token.type
    if COMMENT[t] then
      return true
    end

    if not current then
      local name = command_name(token.node, bufnr)
      if t == ';' and last and last.kind == 'command' then
        -- `\edge{a}{b};`: a command used as a path.
        current = last
        current.kind = 'path'
      elseif ts.ENVIRONMENT[t] or t == 'curly_group' then
        nested(token.node)
        last = nil
        return true
      elseif name == 'foreach' then
        start(token, 'foreach')
        current.loop = 'head'
        return true
      elseif command_like(token) and not paths[name] then
        start(token, 'command')
        return true
      else
        start(token, 'path')
      end
    elseif current.kind == 'command' then
      -- The arguments that follow on the same line, and the `=[...]` of
      -- `\tikzstyle{name}=[...]`.
      local tail = current.tail
      local same_line = token.range[1] == current.range[3]
      if tail == nil and t == 'curly_group' and same_line then
        extend(token)
        return true
      elseif tail == nil and t == '=' and same_line then
        current.tail = 'equals'
        extend(token)
        return true
      elseif tail == 'equals' and t == '[' then
        current.tail = 'options'
        extend(token)
        return true
      elseif tail == 'options' then
        current.tail = t == ']' and 'done' or tail
        extend(token)
        return true
      end
      finish()
      return false
    elseif current.kind == 'foreach' then
      extend(token)
      if current.loop == 'head' then
        if t == 'word' and token.text == 'in' then
          current.loop = 'list'
        end
        return true
      elseif current.loop == 'list' then
        current.loop = 'body'
        -- `\foreach \x in \list {...}`: the macro takes the body as its
        -- argument.
        local body = t == 'generic_command' and ts.child_of_type(token.node, 'curly_group')
        if body then
          nested(body)
          finish()
        end
        return true
      elseif t == 'curly_group' then
        nested(token.node)
        finish()
        return true
      elseif command_name(token.node, bufnr) == 'foreach' then
        current.loop = 'head'
        return true
      end
      -- A loop over a single path, which ends at its `;`.
      current.kind = 'path'
    end

    extend(token)
    if t == ';' and depth == 0 then
      current.semicolon = true
      finish()
    elseif t == '[' or t == '(' then
      depth = depth + 1
    elseif (t == ']' or t == ')') and depth > 0 then
      depth = depth - 1
    end
    return true
  end

  local list = tokens(region, bufnr)
  local i = 1
  while i <= #list do
    if step(list[i]) then
      i = i + 1
    end
  end

  if current then
    if current.kind == 'command' then
      finish()
    else
      -- The `;` is not there (yet): the statement runs on to the end of the
      -- region, which is where a line typed after it still belongs.
      current.reach = body_end(region)
    end
  end
  for _, statement in ipairs(out) do
    statement.tail, statement.loop = nil, nil
  end
end

--- The statements of `picture`, those in loops and scopes included, in
--- document order. A statement comes before the ones nested in it.
---@param picture TSNode
---@param bufnr integer
---@return nvim-tex.TikzStatement[]
function M.statements(picture, bufnr)
  local out = {}
  scan(picture, bufnr, out)
  return out
end

--- The statements of every picture in the buffer, in document order.
---@param bufnr integer|nil
---@return nvim-tex.TikzStatement[]
function M.all_statements(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local out = {}
  local pictures = ts.collect(bufnr, function(node)
    return M.is_picture(node, bufnr)
  end)
  for _, picture in ipairs(pictures) do
    vim.list_extend(out, M.statements(picture, bufnr))
  end
  table.sort(out, function(a, b)
    if a.range[1] ~= b.range[1] then
      return a.range[1] < b.range[1]
    end
    return a.range[2] < b.range[2]
  end)
  return out
end

---@param row integer
---@param col integer
---@param pos integer[]
---@return boolean
local function before(row, col, pos)
  return row < pos[1] or (row == pos[1] and col < pos[2])
end

--- The innermost statement at a position.
---
--- With `opts.reach`, a path whose `;` is missing also covers everything up
--- to the end of its region: what a line typed after it continues.
---@param bufnr integer|nil
---@param row integer 0-indexed
---@param col integer 0-indexed
---@param opts? { reach?: boolean, root?: TSNode }
---@return nvim-tex.TikzStatement|nil
function M.statement_at(bufnr, row, col, opts)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  opts = opts or {}
  local root = opts.root or ts.root(bufnr)
  if not root then
    return nil
  end
  local picture = M.picture(root:descendant_for_range(row, col, row, col), bufnr)
  if not picture then
    return nil
  end

  local found
  for _, statement in ipairs(M.statements(picture, bufnr)) do
    local r = statement.range
    local stop = opts.reach and statement.reach or { r[3], r[4] }
    if not before(row, col, r) and before(row, col, stop) then
      -- Statements nested in this one come after it.
      found = statement
    end
  end
  return found
end

return M
