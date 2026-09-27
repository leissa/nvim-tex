--- Conceal, the tree-sitter way: `\alpha` shows as α, `\mathbb{R}` as ℝ,
--- `x^2` as x², `\'e` as é, `---` as —, `\textbf{bold}` as bold text.
---
--- The replacements are ephemeral extmarks set by a decoration provider for
--- the lines being drawn, so nothing is stored in the buffer and they work
--- the same under tree-sitter highlighting and under `syntax/tex.vim`. They
--- only show with 'conceallevel' at 1 or more, like any conceal; with it at
--- 0 the provider does no work at all.
---
--- What a piece of text is -- a command, a math zone, a superscript -- is
--- read off the parse tree, so `\alpha` in a comment or `^2` outside math is
--- left as it is.
local config = require('nvim-tex.config')
local symbols = require('nvim-tex.conceal.symbols')
local ts = require('nvim-tex.ts')

local M = {}

local api = vim.api
local ns = api.nvim_create_namespace('nvim-tex-conceal')

--- Buffers conceal is enabled for.
---@type table<integer, boolean>
local attached = {}

--- winid -> `{ bufnr, tick, top, bot, rows }`, the items of the range last
--- drawn in that window. Per window, so that two views of one buffer do not
--- keep evicting each other.
---@type table<integer, table>
local cache = {}

local EMPTY = {}

local QUERY = [[
(generic_command) @command
(citation) @citation
(superscript) @superscript
(subscript) @subscript
(enum_item "\\item" @item)
["\\left" "\\right" "\\bigl" "\\bigr" "\\Bigl" "\\Bigr" "\\biggl" "\\biggr" "\\Biggl" "\\Biggr"] @delimiter
(operator "-") @dash
((word) @quote (#lua-match? @quote "^``"))
((word) @quote (#lua-match? @quote "''$"))
]]

local SPACING = {
  ['\\,'] = ' ',
  ['\\:'] = ' ',
  ['\\;'] = ' ',
  ['\\ '] = ' ',
  ['\\quad'] = ' ',
  ['\\qquad'] = ' ',
  ['\\enspace'] = ' ',
  ['\\thinspace'] = ' ',
  ['\\!'] = '',
}

local STYLES = {
  ['\\textbf'] = 'NvimTexBold',
  ['\\textit'] = 'NvimTexItalic',
  ['\\textsl'] = 'NvimTexItalic',
  ['\\emph'] = 'NvimTexItalic',
  ['\\underline'] = 'NvimTexUnderline',
}

local query
---@return vim.treesitter.Query
local function get_query()
  query = query or vim.treesitter.query.parse('latex', QUERY)
  return query
end

--- One replacement: `text` stands in for the range, or `hl` colours it.
---@class NvimTexConceal
---@field col integer
---@field end_col integer
---@field text string|nil
---@field hl string|nil

---@param items table<integer, NvimTexConceal[]>
---@param row integer
---@param col integer
---@param end_col integer
---@param text string|nil
---@param hl string|nil
local function add(items, row, col, end_col, text, hl)
  items[row] = items[row] or {}
  table.insert(items[row], { col = col, end_col = end_col, text = text, hl = hl })
end

---@param node TSNode
---@return boolean
local function in_math(node)
  return ts.ancestor(node, ts.MATH) ~= nil
end

--- The leaf that starts right at (`row`, `col`), if any.
---@param root TSNode
---@param row integer
---@param col integer
---@return TSNode|nil
local function leaf_at(root, row, col)
  local node = root:descendant_for_range(row, col, row, col + 1)
  if node and node:child_count() == 0 then
    local srow, scol = node:start()
    if srow == row and scol == col then
      return node
    end
  end
  return nil
end

--- The text inside a single-line curly group, without the braces.
---@param group TSNode|nil
---@param bufnr integer
---@return string|nil
local function group_text(group, bufnr)
  if not group then
    return nil
  end
  local srow, _, erow = group:range()
  if srow ~= erow then
    return nil
  end
  return (vim.treesitter.get_node_text(group, bufnr):match('^{(.*)}$'))
end

--- `\cmd{x}` on one line, shown as `map[x]`: `\mathbb{R}`, `\"{a}`.
---@param items table
---@param node TSNode
---@param bufnr integer
---@param map table<string, string>
---@return boolean added
local function braced(items, node, bufnr, map)
  local row, col, erow, ecol = node:range()
  local letter = group_text(ts.child_of_type(node, 'curly_group'), bufnr)
  if letter and map[letter] and erow == row then
    add(items, row, col, ecol, map[letter])
    return true
  end
  return false
end

---@param opts table
---@param items table
---@param node TSNode
---@param bufnr integer
---@param root TSNode
local function command(opts, items, node, bufnr, root)
  local name_node = ts.command_name_node(node)
  if not name_node then
    return
  end
  local name = vim.treesitter.get_node_text(name_node, bufnr)
  local row, col, nrow, ncol = name_node:range()

  local custom = opts.custom and opts.custom[name]
  if custom then
    add(items, row, col, ncol, custom)
    return
  end

  if opts.spacing and SPACING[name] then
    add(items, row, col, ncol, SPACING[name])
    return
  end

  local math = in_math(node)
  if math then
    local char = (opts.greek and symbols.greek[name]) or (opts.math_symbols and symbols.math[name])
    if char then
      add(items, row, col, ncol, char)
      return
    end
    local font = opts.math_fonts and symbols.fonts[name:sub(2)]
    if font then
      braced(items, node, bufnr, font)
    end
    return
  end

  local accent = opts.accents and symbols.accents[name]
  if accent then
    -- `\"{a}`: the letter is in the command's own group.
    if braced(items, node, bufnr, accent) then
      return
    end
    -- `\"a`: it is the first character of the word that follows.
    local word = leaf_at(root, nrow, ncol)
    if word then
      local first = vim.treesitter.get_node_text(word, bufnr):sub(1, 1)
      if accent[first] then
        add(items, row, col, ncol + 1, accent[first])
      end
    end
    return
  end

  local _, _, erow, ecol = node:range()
  if opts.text_symbols and symbols.text[name] and erow == row then
    add(items, row, col, ecol, symbols.text[name])
    return
  end

  local hl = opts.styles and STYLES[name]
  local group = hl and ts.child_of_type(node, 'curly_group')
  if group then
    local grow, gcol, gerow, gecol = group:range()
    if grow ~= row then
      return
    end
    add(items, row, col, gcol + 1, '')
    add(items, gerow, gecol - 1, gecol, '')
    -- The styled text, one line at a time: an extmark is set for the line
    -- being drawn, and a multi-line one starting above the window would be
    -- missed.
    for r = grow, gerow do
      local line = api.nvim_buf_get_lines(bufnr, r, r + 1, false)[1] or ''
      local from = r == grow and gcol + 1 or 0
      local to = r == gerow and gecol - 1 or #line
      if to > from then
        add(items, r, from, to, nil, hl)
      end
    end
  end
end

---@param opts table
---@param items table
---@param node TSNode
local function citation(opts, items, node)
  if not opts.cites or ts.child_of_type(node, 'brack_group') then
    return
  end
  local list = node:named_child(node:named_child_count() - 1)
  if not list then
    return
  end
  local row, col = node:start()
  local lrow, lcol, lerow, lecol = list:range()
  if lrow ~= row then
    return
  end
  add(items, row, col, lcol + 1, '[')
  add(items, lerow, lecol - 1, lecol, ']')
end

---@param opts table
---@param items table
---@param node TSNode
---@param bufnr integer
---@param map table<string, string>
local function script(opts, items, node, bufnr, map)
  if not opts.math_super_sub or not in_math(node) then
    return
  end
  local row, col, erow, ecol = node:range()
  if row ~= erow then
    return
  end
  local text = vim.treesitter.get_node_text(node, bufnr)
  local body = text:sub(2)
  local braced = body:match('^{(.*)}$')
  local chars = braced or body
  if chars == '' then
    return
  end
  for i = 1, #chars do
    if not map[chars:sub(i, i)] then
      return
    end
  end

  if not braced then
    add(items, row, col, ecol, map[chars])
    return
  end
  -- `^{12}`: the `^{` goes with the first character, the `}` with the last.
  local first = col + 2
  for i = 1, #chars do
    local s = first + i - 1
    local from = i == 1 and col or s
    local to = i == #chars and ecol or s + 1
    add(items, row, from, to, map[chars:sub(i, i)])
  end
end

---@param opts table
---@param items table
---@param node TSNode
---@param bufnr integer
---@param root TSNode
local function delimiter(opts, items, node, bufnr, root)
  if not opts.math_delimiters then
    return
  end
  local row, col, _, ecol = node:range()
  -- `\left.` and `\right.` stand for no delimiter at all.
  local next_leaf = leaf_at(root, row, ecol)
  if next_leaf and vim.treesitter.get_node_text(next_leaf, bufnr) == '.' then
    ecol = ecol + 1
  end
  add(items, row, col, ecol, '')
end

---@param opts table
---@param items table
---@param node TSNode
local function dash(opts, items, node)
  if not opts.ligatures or in_math(node) then
    return
  end
  local function is_dash(n)
    return n and n:type() == 'operator' and n:child(0) and n:child(0):type() == '-'
  end
  local row, col = node:start()
  local prev = node:prev_sibling()
  if is_dash(prev) and select(2, prev:end_()) == col then
    return
  end
  local last, count = node, 1
  local nxt = node:next_sibling()
  while is_dash(nxt) and select(2, nxt:start()) == select(2, last:end_()) do
    last, count = nxt, count + 1
    nxt = nxt:next_sibling()
  end
  local char = ({ [2] = '–', [3] = '—' })[count]
  if char then
    add(items, row, col, select(2, last:end_()), char)
  end
end

---@param opts table
---@param items table
---@param node TSNode
---@param bufnr integer
local function quote(opts, items, node, bufnr)
  if not opts.ligatures or in_math(node) then
    return
  end
  local text = vim.treesitter.get_node_text(node, bufnr)
  local row, col, _, ecol = node:range()
  local opens = text:sub(1, 2) == '``'
  if opens then
    add(items, row, col, col + 2, '“')
  end
  -- A lone `''` closes; in ` ``'' ` the two must not overlap.
  if text:sub(-2) == "''" and #text >= (opens and 4 or 2) then
    add(items, row, ecol - 2, ecol, '”')
  end
end

--- The replacements for rows `top` to `bot` (0-indexed, end exclusive).
---@param bufnr integer
---@param top integer
---@param bot integer
---@return table<integer, NvimTexConceal[]> rows
function M.items(bufnr, top, bot)
  local items = {}
  local root = ts.root(bufnr)
  if not root then
    return items
  end
  local opts = config.get('conceal') or {}
  local q = get_query()
  -- A word can match both quote patterns.
  local seen = {}
  for id, node in q:iter_captures(root, bufnr, top, bot) do
    local capture = q.captures[id]
    if capture == 'command' then
      command(opts, items, node, bufnr, root)
    elseif capture == 'citation' then
      citation(opts, items, node)
    elseif capture == 'superscript' then
      script(opts, items, node, bufnr, symbols.superscript)
    elseif capture == 'subscript' then
      script(opts, items, node, bufnr, symbols.subscript)
    elseif capture == 'item' then
      if opts.item then
        local row, col, _, ecol = node:range()
        add(items, row, col, ecol, '•')
      end
    elseif capture == 'delimiter' then
      if in_math(node) then
        delimiter(opts, items, node, bufnr, root)
      end
    elseif capture == 'dash' then
      dash(opts, items, node)
    elseif capture == 'quote' and not seen[node:id()] then
      seen[node:id()] = true
      quote(opts, items, node, bufnr)
    end
  end
  return items
end

local function define_highlights()
  api.nvim_set_hl(0, 'NvimTexBold', { default = true, link = '@markup.strong' })
  api.nvim_set_hl(0, 'NvimTexItalic', { default = true, link = '@markup.italic' })
  api.nvim_set_hl(0, 'NvimTexUnderline', { default = true, link = '@markup.underline' })
end

local provider_set = false

local function set_provider()
  if provider_set then
    return
  end
  provider_set = true
  define_highlights()
  local group = api.nvim_create_augroup('nvim-tex-conceal', { clear = true })
  api.nvim_create_autocmd('ColorScheme', { group = group, callback = define_highlights })
  api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      cache[tonumber(args.match)] = nil
    end,
  })

  api.nvim_set_decoration_provider(ns, {
    on_win = function(_, win, bufnr, top, bot)
      if not attached[bufnr] or vim.wo[win].conceallevel == 0 then
        return false
      end
      local tick = api.nvim_buf_get_changedtick(bufnr)
      local cached = cache[win]
      if not (cached and cached.bufnr == bufnr and cached.tick == tick and cached.top <= top and cached.bot > bot) then
        local ok, rows = pcall(M.items, bufnr, top, bot + 1)
        cache[win] = { bufnr = bufnr, tick = tick, top = top, bot = bot + 1, rows = ok and rows or EMPTY }
      end
    end,
    on_line = function(_, win, bufnr, row)
      local cached = cache[win]
      for _, item in ipairs(cached and cached.rows[row] or EMPTY) do
        pcall(api.nvim_buf_set_extmark, bufnr, ns, row, item.col, {
          end_row = row,
          end_col = item.end_col,
          conceal = item.text,
          hl_group = item.hl,
          ephemeral = true,
          priority = 110,
        })
      end
    end,
  })
end

--- Conceal in `bufnr`.
---@param bufnr integer
function M.attach(bufnr)
  set_provider()
  if attached[bufnr] then
    return
  end
  attached[bufnr] = true
  api.nvim_create_autocmd({ 'BufWipeout', 'BufUnload' }, {
    buffer = bufnr,
    once = true,
    callback = function()
      attached[bufnr] = nil
    end,
  })
end

return M
