--- Insert mode math mappings, vimtex's `imaps`.
---
--- A short sequence behind a leader key -- a backtick by default -- expands
--- into a LaTeX command: `` `a `` gives `\alpha`, `` `8 `` gives `\infty`.
--- The expansion only happens inside a math zone; in running text the typed
--- keys are inserted unchanged, so the leader stays usable for quotes.
---
--- Whether the cursor sits in math is decided by `nvim-tex.ts`, from the parse
--- tree rather than from syntax groups.
local config = require('nvim-tex.config')
local ts = require('nvim-tex.ts')
local util = require('nvim-tex.util')

--- One insert mode mapping.
---@class nvim-tex.Imap
---@field lhs string typed after the leader, taken literally
---@field rhs? string|fun(lhs: string): string the text to insert
---@field style? string shorthand for an rhs built by `M.style`
---@field leader? string overrides `imaps.leader`
---@field wrapper? string|fun(lhs: string, expand: fun(): string): string

local M = {}

local ESC = '\27'

--- Buffers the mappings were created in, so `M.add` can reach them.
---@type table<integer, boolean>
local attached = {}

--- Maps registered at run time through `M.add`.
---@type nvim-tex.Imap[]
local extra = {}

--- Decide whether an entry expands at all.
---
--- A wrapper receives the typed sequence and a function producing the
--- expansion, and returns the text to insert. `entry.wrapper` names one of
--- these, or is a function of the same shape.
---@type table<string, fun(lhs: string, expand: fun(): string): string>
M.wrappers = {
  --- Expand in math zones, insert the typed keys everywhere else.
  math = function(lhs, expand)
    return ts.in_math(0) and expand() or lhs
  end,
  --- Expand unconditionally.
  trivial = function(_, expand)
    return expand()
  end,
}

--- An rhs that reads one more keystroke and wraps it in `command`.
---
--- With the default list, `#bx` gives `\mathbf{x}`.
---@param command string
---@return fun(lhs: string): string
function M.style(command)
  return function(lhs)
    local ok, char = pcall(vim.fn.getcharstr)
    if not ok then
      return lhs
    end
    if char == nil or char == '' or char == ESC then
      -- Aborted with <Esc>; leave the buffer alone.
      return ''
    end
    return '\\' .. command .. '{' .. char .. '}'
  end
end

--- The leader of an entry.
---@param entry nvim-tex.Imap
---@return string
local function leader_of(entry)
  return entry.leader or config.get('imaps', 'leader') or ''
end

--- The full typed sequence of an entry.
---@param entry nvim-tex.Imap
---@return string
function M.lhs(entry)
  return leader_of(entry) .. entry.lhs
end

--- A short description of what an entry inserts, for `:TexImaps`.
---@param entry nvim-tex.Imap
---@return string
function M.rhs_label(entry)
  if entry.style then
    return '\\' .. entry.style .. '{<char>}'
  end
  if type(entry.rhs) == 'function' then
    return '<function>'
  end
  return tostring(entry.rhs)
end

--- The entries that are actually mapped: the configured list without the
--- disabled ones, plus whatever `M.add` collected.
---@return nvim-tex.Imap[]
function M.entries()
  local opts = config.get('imaps')
  local disabled = {}
  for _, lhs in ipairs(opts.disabled or {}) do
    disabled[lhs] = true
  end

  local out = {}
  for _, entry in ipairs(opts.list or {}) do
    if entry.lhs and not disabled[entry.lhs] then
      out[#out + 1] = entry
    end
  end
  for _, entry in ipairs(extra) do
    if entry.lhs and not disabled[entry.lhs] then
      out[#out + 1] = entry
    end
  end
  return out
end

---@param entry nvim-tex.Imap
---@return fun(lhs: string, expand: fun(): string): string
local function wrapper_of(entry)
  local wrapper = entry.wrapper or 'math'
  if type(wrapper) == 'function' then
    return wrapper
  end
  local known = M.wrappers[wrapper]
  if not known then
    util.warn(("unknown imaps wrapper '%s'"):format(tostring(wrapper)))
    return M.wrappers.math
  end
  return known
end

--- Create the mapping for one entry in `bufnr`.
---@param bufnr integer
---@param entry nvim-tex.Imap
local function create(bufnr, entry)
  if not entry.lhs or not (entry.rhs or entry.style) then
    return
  end

  local lhs = M.lhs(entry)
  local wrapper = wrapper_of(entry)
  local rhs = entry.rhs or M.style(entry.style)
  local expand = function()
    if type(rhs) == 'function' then
      return rhs(lhs) or ''
    end
    return rhs
  end

  vim.keymap.set('i', (lhs:gsub('<', '<lt>')), function()
    return wrapper(lhs, expand)
  end, {
    buffer = bufnr,
    expr = true,
    -- The expansion is text, not keys: a `<` in it stays a `<`.
    replace_keycodes = false,
    nowait = true,
    silent = true,
    desc = ('nvim-tex: imap %s -> %s'):format(lhs, M.rhs_label(entry)),
  })
end

--- Create the insert mode mappings in `bufnr`.
---@param bufnr integer
function M.attach(bufnr)
  if not config.get('imaps', 'enabled') then
    return
  end
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  attached[bufnr] = true

  for _, entry in ipairs(M.entries()) do
    create(bufnr, entry)
  end
end

--- Register one more map, in every attached buffer and in those to come.
---
--- >lua
---     require('nvim-tex.imaps').add({ lhs = 'oo', rhs = '\\circ' })
--- <
---@param entry nvim-tex.Imap
function M.add(entry)
  extra[#extra + 1] = entry
  for bufnr in pairs(attached) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      create(bufnr, entry)
    else
      attached[bufnr] = nil
    end
  end
end

--- Show every mapping in a scratch buffer.
function M.list()
  local entries = M.entries()
  if #entries == 0 then
    util.info('no insert mode mappings')
    return
  end

  local lines = {}
  for _, entry in ipairs(entries) do
    local wrapper = type(entry.wrapper) == 'string' and entry.wrapper or (entry.wrapper and 'custom' or 'math')
    lines[#lines + 1] = ('%-8s ->  %-24s %s'):format(M.lhs(entry), M.rhs_label(entry), wrapper)
  end
  util.scratch('nvim-tex://imaps', lines, { height = math.min(#lines + 1, 20) })
end

return M
