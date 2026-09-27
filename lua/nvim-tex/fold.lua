--- LaTeX folding.
---
--- Neovim's `vim.treesitter.foldexpr()` already does the hard part -- it
--- computes fold levels asynchronously and updates them incrementally as the
--- tree changes -- but it needs a `folds` query, and Neovim ships none for
--- LaTeX. nvim-tex installs its own with `vim.treesitter.query.set`, which
--- also takes precedence over the one nvim-treesitter may provide.
---
--- The query itself is fixed; what it folds is decided by predicates that
--- read the `fold` options when the tree is matched. Neovim 0.10 memoizes
--- `query.get`, so a query rebuilt from changed options would never be seen,
--- and this way a change needs no more than a refold.
---
--- Two folds are not a single node in the tree, and get their range from a
--- directive: the preamble runs from `\documentclass` to the line before
--- `\begin{document}`, and a section runs up to the line before whatever
--- follows it, so the blank lines between sections fold with them.
local config = require('nvim-tex.config')
local ts = require('nvim-tex.ts')
local util = require('nvim-tex.util')

local M = {}

--- The node types of `ts.SECTION` and `ts.VERBATIM`, for the query.
---@param set table<string, boolean>
---@return string
local function alternatives(set)
  local types = vim.tbl_keys(set)
  table.sort(types)
  return table.concat(
    vim.tbl_map(function(t)
      return '(' .. t .. ')'
    end, types),
    ' '
  )
end

local registered = false

local function register()
  if registered then
    return
  end
  registered = true
  local opts = ts.HANDLER_OPTS

  -- `(#nvim-tex-fold? "sections")`: is this kind of fold switched on?
  vim.treesitter.query.add_predicate('nvim-tex-fold?', function(_, _, _, predicate)
    return config.get('fold', predicate[2]) == true
  end, opts)

  -- `(#nvim-tex-env? @name)`: may the environment called `@name` fold?
  vim.treesitter.query.add_predicate('nvim-tex-env?', function(match, _, source, predicate)
    local node = ts.captured(match, predicate[2])
    if not node then
      return false
    end
    local name = ts.unstarred(vim.trim(vim.treesitter.get_node_text(node, source)))
    return not vim.tbl_contains(config.get('fold', 'ignored_envs') or {}, name)
  end, opts)

  vim.treesitter.query.add_directive('nvim-tex-preamble!', function(match, _, source, predicate, metadata)
    local id = predicate[2]
    local node = ts.captured(match, id)
    if not node then
      return
    end
    local srow, scol = node:start()
    local sibling = node:next_named_sibling()
    while sibling and ts.env_name(sibling, source) ~= 'document' do
      sibling = sibling:next_named_sibling()
    end
    -- Without a document environment there is no preamble to speak of; a
    -- single-line range folds nothing.
    local stop = sibling and sibling:start() or srow
    ts.set_range(metadata, id, { srow, scol, stop, 0 })
  end, opts)

  vim.treesitter.query.add_directive('nvim-tex-section!', function(match, _, _, predicate, metadata)
    local id = predicate[2]
    local node = ts.captured(match, id)
    if not node then
      return
    end
    local srow, scol, erow, ecol = node:range()
    -- The last subsection of a section runs as far as the section does.
    local outer = node
    while not outer:next_named_sibling() and outer:parent() and ts.SECTION[outer:parent():type()] do
      outer = outer:parent()
    end
    local next_node = outer:next_named_sibling()
    local nrow = next_node and next_node:start()
    if nrow and nrow > erow then
      ts.set_range(metadata, id, { srow, scol, nrow, 0 })
    else
      ts.set_range(metadata, id, { srow, scol, erow, ecol })
    end
  end, opts)
end

--- The `folds` query.
---@return string
function M.query_source()
  return table.concat({
    '((class_include) @fold (#nvim-tex-fold? "preamble") (#nvim-tex-preamble! @fold))',
    ('([%s] @fold (#nvim-tex-fold? "sections") (#nvim-tex-section! @fold))'):format(alternatives(ts.SECTION)),
    '([(generic_environment begin: (begin name: (curly_group_text text: (text) @_name)))'
      .. ' (math_environment begin: (begin name: (curly_group_text text: (text) @_name)))] @fold'
      .. ' (#nvim-tex-fold? "envs") (#nvim-tex-env? @_name))',
    ('([%s] @fold (#nvim-tex-fold? "envs"))'):format(alternatives(ts.VERBATIM)),
    '((displayed_equation) @fold (#nvim-tex-fold? "math"))',
    '([(comment_environment) (block_comment)] @fold (#nvim-tex-fold? "comments"))',
  }, '\n')
end

local installed = false

--- Install the `folds` query, once.
---@return boolean ok
function M.install()
  if installed then
    return true
  end
  register()
  local ok, err = pcall(vim.treesitter.query.set, 'latex', 'folds', M.query_source())
  if not ok then
    util.error('could not install the fold query: ' .. tostring(err))
    return false
  end
  installed = true
  return true
end

--- Fold `bufnr` in the window showing it. 'foldmethod' and 'foldexpr' are
--- window-local; Neovim carries them over to windows that open the buffer
--- later.
---@param bufnr integer
function M.attach(bufnr)
  if not M.install() then
    return
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.opt_local.foldmethod = 'expr'
    vim.opt_local.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
  end)
end

return M
