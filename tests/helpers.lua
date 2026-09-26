--- Fixtures shared by the spec files.
---
--- Everything created through these helpers is remembered and torn down by
--- `H.cleanup`, which the spec files call from an `after_each`.
local H = {}

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)

---@type string[]
local tmpdirs = {}
---@type integer[]
local buffers = {}

--- `vim.notify` is recorded rather than printed: the plugin reports problems
--- through it, so the tests both keep the output clean and get to assert on
--- what was reported.
---@type table[]
H.notifications = {}

vim.notify = function(message, level)
  H.notifications[#H.notifications + 1] = { message = message, level = level }
end

--- Was a message matching `pattern` notified?
---@param pattern string
---@return boolean
function H.notified(pattern)
  for _, notification in ipairs(H.notifications) do
    if tostring(notification.message):match(pattern) then
      return true
    end
  end
  return false
end

--- Is the `latex` tree-sitter parser installed?
---@return boolean
function H.has_parser()
  -- `language.add` cannot be asked: 0.10 returns nothing at all and raises
  -- when the parser is missing, while 0.11 and later return `true` or
  -- `nil, err`. Building a parser works the same way everywhere.
  return (pcall(vim.treesitter.get_string_parser, '', 'latex'))
end

--- Skip the current test unless the `latex` parser is available. CI sets
--- `NVIM_TEX_REQUIRE_PARSER=1` so that a parser it failed to build turns into
--- a red build rather than a suite that quietly tests half as much.
function H.need_parser()
  if H.has_parser() then
    return
  end
  if vim.env.NVIM_TEX_REQUIRE_PARSER == '1' then
    error("the 'latex' tree-sitter parser is required but was not found")
  end
  T.skip("the 'latex' tree-sitter parser is not installed")
end

--- A fresh temporary directory, removed by `H.cleanup`.
---@return string
function H.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  tmpdirs[#tmpdirs + 1] = dir
  return (vim.fs.normalize(dir))
end

--- Write `contents` to `path`, creating parent directories as needed.
---@param path string
---@param contents string|string[]
---@return string path
function H.write(path, contents)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local lines = type(contents) == 'table' and contents or vim.split(contents, '\n', { plain = true })
  vim.fn.writefile(lines, path)
  return (vim.fs.normalize(path))
end

--- A buffer holding `lines`, shown in the current window.
---@param lines string|string[]
---@param opts table|nil `{ name = string, filetype = string }`
---@return integer bufnr
function H.buf(lines, opts)
  opts = opts or {}
  if type(lines) == 'string' then
    lines = vim.split(lines, '\n', { plain = true })
  end

  local bufnr = vim.api.nvim_create_buf(true, false)
  if opts.name then
    vim.api.nvim_buf_set_name(bufnr, opts.name)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = opts.filetype or 'tex'
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  buffers[#buffers + 1] = bufnr
  return bufnr
end

--- Move the cursor. `row` is 1-indexed, `col` 0-indexed.
---@param row integer
---@param col integer|nil
function H.cursor(row, col)
  vim.api.nvim_win_set_cursor(0, { row, col or 0 })
end

--- Place the cursor on the first `needle` in the buffer and return its
--- position. Makes the specs read in terms of the text rather than numbers.
---@param needle string plain text, not a pattern
---@param bufnr integer|nil
---@return integer row, integer col
function H.cursor_at(needle, bufnr)
  bufnr = bufnr or 0
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local col = line:find(needle, 1, true)
    if col then
      vim.api.nvim_win_set_cursor(0, { row, col - 1 })
      return row, col - 1
    end
  end
  error(("no %q in the buffer"):format(needle))
end

---@param bufnr integer|nil
---@return string[]
function H.lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)
end

---@param bufnr integer|nil
---@return string
function H.text(bufnr)
  return table.concat(H.lines(bufnr), '\n')
end

--- Run `fn`, which is expected to leave a visual selection, and report it.
---@param fn function
---@return table|nil `{ mode, srow, scol, erow, ecol }`, 1-indexed rows
function H.selection(fn)
  fn()
  local mode = vim.fn.mode()
  if not mode:match('^[vV\22]') then
    return nil
  end
  local anchor = vim.fn.getpos('v')
  local cursor = vim.fn.getpos('.')
  vim.cmd('normal! ' .. ESC)
  return {
    mode = mode,
    srow = anchor[2],
    scol = anchor[3] - 1,
    erow = cursor[2],
    ecol = cursor[3] - 1,
  }
end

--- The text a `H.selection` result covers, characterwise.
---@param sel table
---@return string
function H.selected_text(sel)
  if sel.mode == 'V' then
    return table.concat(vim.api.nvim_buf_get_lines(0, sel.srow - 1, sel.erow, false), '\n')
  end
  return table.concat(
    vim.api.nvim_buf_get_text(0, sel.srow - 1, sel.scol, sel.erow - 1, sel.ecol + 1, {}),
    '\n'
  )
end

--- A project table as `nvim-tex.project` would build it, without touching a
--- buffer. `main` must be an absolute path.
---@param main string
---@param overrides table|nil
---@return table
function H.project(main, overrides)
  local dir = vim.fs.dirname(main)
  local project = {
    main = main,
    root = dir,
    name = vim.fn.fnamemodify(main, ':t:r'),
    out_dir = dir,
    aux_dir = dir,
    out_dir_set = false,
    aux_dir_set = false,
    output = {},
  }
  return vim.tbl_extend('force', project, overrides or {})
end

--- Reset the plugin's global state between tests.
function H.reset()
  require('nvim-tex.config').setup({})
  require('nvim-tex.qf').set_level('warning')
  local project = require('nvim-tex.project')
  project.projects = {}
end

--- Remove every buffer, window and temporary directory a test created.
function H.cleanup()
  -- Feeding <Esc> drops a visual selection and, just as importantly, the
  -- pending count that a `2]]` left behind: `v:count1` would otherwise still
  -- be 2 the next time a mapping's function is called directly.
  vim.api.nvim_feedkeys(ESC, 'nx', false)
  vim.cmd('silent! only')

  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  buffers = {}

  for _, dir in ipairs(tmpdirs) do
    vim.fn.delete(dir, 'rf')
  end
  tmpdirs = {}

  vim.fn.setqflist({}, 'r')
  H.notifications = {}
  H.reset()
end

return H
