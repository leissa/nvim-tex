--- LaTeX log parsing into the quickfix list.
---
--- The parser tracks the `(file ... )` stack that TeX prints so that warnings
--- without an explicit file name -- most of them -- still get attributed to
--- the right file. This only works reliably when TeX does not wrap its output
--- at 79 columns, which is why the compiler exports `max_print_line`.
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')
local util = require('nvim-tex.util')

local M = {}

--- Messages that are noise for virtually everybody.
local DEFAULT_IGNORE = {
  'Underfull \\\\hbox %(badness',
  'Overfull \\\\hbox %(%d+%.%d+pt too wide%)',
  'Font shape .* undefined',
  'Font shape .* in size <[^>]+> not available',
  'Package hyperref Warning: Token not allowed in a PDF string',
  'Package typearea Warning: Bad type area settings!',
  'Package fancyhdr Warning: \\\\headheight is too small',
}

---@param message string
---@return boolean
local function ignored(message)
  for _, pattern in ipairs(DEFAULT_IGNORE) do
    if message:match(pattern) then
      return true
    end
  end
  for _, pattern in ipairs(config.get('qf', 'ignore_filters') or {}) do
    if message:match(pattern) then
      return true
    end
  end
  return false
end

--- Pull every `(path` / `)` token out of a log line and update the file stack.
---
--- TeX writes the opening parenthesis immediately before the file name and the
--- closing one when it is done with the file, interleaved with arbitrary other
--- output, so the stack is maintained character by character.
---@param line string
---@param stack string[]
---@param root string
local function update_stack(line, stack, root)
  local i = 1
  local len = #line
  while i <= len do
    local char = line:sub(i, i)
    if char == '(' then
      local rest = line:sub(i + 1)
      -- A file name runs until whitespace or another parenthesis.
      local path = rest:match('^([^%s%(%)]+)')
      if path and path:match('%.%a+$') then
        -- Advance past the raw match, not past the resolved path.
        i = i + #path
        if not path:match('^[/~]') then
          path = util.join(root, path)
        end
        stack[#stack + 1] = util.normalize(path)
      else
        -- Not a file: push a placeholder so the matching `)` pops it.
        stack[#stack + 1] = stack[#stack] or root
      end
    elseif char == ')' then
      if #stack > 0 then
        table.remove(stack)
      end
    end
    i = i + 1
  end
end

---@param stack string[]
---@param fallback string
---@return string
local function current_file(stack, fallback)
  return stack[#stack] or fallback
end

--- Parse a LaTeX `.log` file into quickfix items.
---@param logfile string
---@param root string directory relative paths in the log resolve against
---@param main string file used when nothing better is known
---@return table[] items
function M.parse_log(logfile, root, main)
  local lines = util.readlines(logfile)
  local items = {}
  local stack = {}

  ---@param item table
  local function push(item)
    if item.text and item.text ~= '' and not ignored(item.text) then
      item.text = vim.trim(item.text)
      items[#items + 1] = item
    end
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]

    -- `-file-line-error` format: `./file.tex:12: Undefined control sequence.`
    local file, lnum, message = line:match('^(..-):(%d+):%s*(.+)$')
    if file and lnum and not file:match('^%s*$') then
      if not file:match('^[/~]') then
        file = util.join(root, file)
      end
      file = util.normalize(file)
      push({ filename = file, lnum = tonumber(lnum), type = 'E', text = message })
      i = i + 1
      goto continue
    end

    -- Plain TeX error: `! Undefined control sequence.` with the line number
    -- following a few lines later as `l.42 ...`.
    message = line:match('^!%s*(.+)$')
    if message then
      local err_lnum = 0
      for j = i + 1, math.min(i + 12, #lines) do
        local candidate = lines[j]:match('^l%.(%d+)')
        if candidate then
          err_lnum = tonumber(candidate)
          break
        end
      end
      push({
        filename = current_file(stack, main),
        lnum = err_lnum,
        type = 'E',
        text = message,
      })
      i = i + 1
      goto continue
    end

    -- Warnings. They may continue on following lines until a blank line, and
    -- the interesting `on input line N` part is often on the continuation.
    local warning = line:match('^(LaTeX Warning:%s*.+)$')
      or line:match('^(LaTeX Font Warning:%s*.+)$')
      or line:match('^(Package%s+%S+%s+Warning:%s*.+)$')
      or line:match('^(Class%s+%S+%s+Warning:%s*.+)$')
      or line:match('^(Package%s+%S+%s+Info:%s*.+ on input line %d+.)$')
    if warning then
      local text = warning
      local j = i + 1
      while j <= #lines and lines[j] ~= '' and not lines[j]:match('^[%(%)!]') and j <= i + 4 do
        local cont = vim.trim(lines[j])
        if cont == '' or cont:match('^[A-Z][%a%s]+:%s') then
          break
        end
        text = text .. ' ' .. cont
        j = j + 1
      end
      local warn_lnum = tonumber(text:match('on input line (%d+)')) or 0
      push({
        filename = current_file(stack, main),
        lnum = warn_lnum,
        type = 'W',
        text = text,
      })
      update_stack(line, stack, root)
      i = j
      goto continue
    end

    -- Box warnings carry their own line range.
    local kind, box_lnum = line:match('^(Overfull \\[hv]box .*) at lines (%d+)')
    if not kind then
      kind, box_lnum = line:match('^(Underfull \\[hv]box .*) at lines (%d+)')
    end
    if not kind then
      kind, box_lnum = line:match('^(Overfull \\[hv]box .*) at line (%d+)')
    end
    if not kind then
      kind, box_lnum = line:match('^(Underfull \\[hv]box .*) at line (%d+)')
    end
    if kind then
      push({
        filename = current_file(stack, main),
        lnum = tonumber(box_lnum),
        type = 'W',
        text = kind,
      })
      update_stack(line, stack, root)
      i = i + 1
      goto continue
    end

    update_stack(line, stack, root)
    i = i + 1
    ::continue::
  end

  return items
end

--- Parse a BibTeX/Biber `.blg` log for citation problems.
---@param blgfile string
---@param main string
---@return table[]
function M.parse_blg(blgfile, main)
  local items = {}
  for _, line in ipairs(util.readlines(blgfile)) do
    local message = line:match("^Warning%-%-(.+)$")
    if message then
      local lnum = tonumber(message:match('line (%d+)')) or 0
      local file = message:match('in ([%w%-_%.]+%.bib)')
      if not ignored(message) then
        items[#items + 1] = {
          filename = file or main,
          lnum = lnum,
          type = 'W',
          text = message,
        }
      end
    end
  end
  return items
end

--- Collect all diagnostics for `project`.
---@param project table
---@return table[]
function M.collect(project)
  local items = M.parse_log(project_mod.log_file(project), project.root, project.main)
  local blg = util.join(project.aux_dir, project.name .. '.blg')
  if util.is_file(blg) then
    vim.list_extend(items, M.parse_blg(blg, project.main))
  end
  return items
end

--- Fill the quickfix list from `project`'s log and open it if configured.
---@param project table
---@param opts table|nil `{ force_open = boolean, silent = boolean }`
---@return integer errors, integer warnings
function M.update(project, opts)
  opts = opts or {}
  if not config.get('qf', 'enabled') then
    return 0, 0
  end

  local items = M.collect(project)
  vim.fn.setqflist({}, ' ', {
    title = 'nvim-tex: ' .. vim.fn.fnamemodify(project.main, ':t'),
    items = items,
  })
  project.qf_items = items

  local errors, warnings = 0, 0
  for _, item in ipairs(items) do
    if item.type == 'E' then
      errors = errors + 1
    else
      warnings = warnings + 1
    end
  end
  project.qf_errors, project.qf_warnings = errors, warnings

  local should_open = opts.force_open
    or (config.get('qf', 'auto_open') and (errors > 0 or (warnings > 0 and config.get('qf', 'open_on_warning'))))

  if should_open then
    M.open(opts.silent)
  elseif config.get('qf', 'auto_close') and #items == 0 then
    M.close()
  end

  return errors, warnings
end

---@param silent boolean|nil keep the cursor in the current window
function M.open(silent)
  local items = vim.fn.getqflist()
  if #items == 0 then
    util.info('No errors or warnings')
    return
  end

  local winid = vim.api.nvim_get_current_win()
  vim.cmd('botright copen ' .. (config.get('qf', 'height') or 8))
  if config.get('qf', 'autojump') then
    vim.cmd('cfirst')
  elseif silent ~= false then
    vim.api.nvim_set_current_win(winid)
  end
end

function M.close()
  vim.cmd('cclose')
end

return M
