--- LaTeX log parsing into the quickfix list.
---
--- The parser tracks the `(file ... )` stack that TeX prints so that warnings
--- without an explicit file name -- most of them -- still get attributed to
--- the right file. This only works reliably when TeX does not wrap its output
--- at 79 columns, which is why the compiler exports `max_print_line`.
---
--- A LaTeX run is chatty: a document of any size produces far more chatter
--- than actionable diagnostics. Rather than dropping that chatter outright,
--- every message is classified into one of three severities and the quickfix
--- list only shows those at or above `qf.level` (`'warning'` by default):
---
---   E (error)   the build broke;
---   W (warning) something in the document is probably wrong -- undefined
---               references, missing citations, package warnings;
---   I (info)    TeX narrating what it did -- font substitutions, package
---               infos, missing characters -- which says nothing about the
---               document's correctness.
---
--- `:TexQfLevel` cycles the level, so the hidden messages stay one keystroke
--- away instead of being lost. Over/underfull boxes are the exception: they
--- are dropped at parse time unless `qf.boxes` is set, because they are by
--- far the largest part of a log and are a typesetting detail rather than
--- something wrong with the document.
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')
local util = require('nvim-tex.util')

local M = {}

--- Ordering of the severities, lowest (most severe) first.
local RANK = { E = 1, W = 2, I = 3 }

--- `qf.level` values, mapped onto the same scale.
local LEVEL_RANK = { error = 1, warning = 2, info = 3 }

--- Cycled through by `M.cycle_level`.
local LEVEL_ORDER = { 'error', 'warning', 'info' }

--- Messages that are noise for virtually everybody. These are dropped
--- outright; anything that is merely verbose belongs in `INFO_PATTERNS`
--- instead, where the level filter can bring it back.
local DEFAULT_IGNORE = {
  'Package hyperref Warning: Token not allowed in a PDF string',
  'Package typearea Warning: Bad type area settings!',
  'Package fancyhdr Warning: \\headheight is too small',
}

--- Messages TeX emits to describe what it did rather than to report a problem.
--- Matched against the assembled message text, so continuation lines that were
--- folded into it do not affect the classification.
local INFO_PATTERNS = {
  '^Package%s+%S+%s+Info:',
  '^Class%s+%S+%s+Info:',
  '^LaTeX Info:',
  '^LaTeX Font Warning:',
  '^Font shape',
  '^Missing character:',
}

--- Session override for `qf.level`, set by `M.set_level`.
---@type string|nil
local level_override = nil

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

--- Downgrade a warning to info when it is only TeX narrating its own work.
---@param text string
---@param default string
---@return string
local function severity(text, default)
  if default ~= 'W' then
    return default
  end
  for _, pattern in ipairs(INFO_PATTERNS) do
    if text:match(pattern) then
      return 'I'
    end
  end
  return default
end

--- The severity currently shown, honouring a `M.set_level` override.
---@return string
function M.level()
  local level = level_override or config.get('qf', 'level') or 'warning'
  if not LEVEL_RANK[level] then
    util.warn(("unknown qf.level %q, falling back to 'warning'"):format(tostring(level)))
    return 'warning'
  end
  return level
end

--- Show messages at or above `level` (`'error'`, `'warning'` or `'info'`).
---@param level string
function M.set_level(level)
  if not LEVEL_RANK[level] then
    util.error(("unknown qf.level %q, expected one of: %s"):format(
      tostring(level), table.concat(LEVEL_ORDER, ', ')))
    return
  end
  level_override = level
end

--- Step to the next severity, wrapping around.
---@return string the new level
function M.cycle_level()
  local current = M.level()
  for i, level in ipairs(LEVEL_ORDER) do
    if level == current then
      level_override = LEVEL_ORDER[i % #LEVEL_ORDER + 1]
      break
    end
  end
  return M.level()
end

---@return string[]
function M.levels()
  return vim.deepcopy(LEVEL_ORDER)
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

--- Does `line` start a diagnostic of its own? Warnings are folded together
--- with their continuation lines, and without this the fold would swallow the
--- message that follows -- including errors.
---@param line string
---@return boolean
local function starts_message(line)
  return line:match('^!')
      or line:match('^%a[^:]*%.%a+:%d+:')
      or line:match('^%.?/?%a[^:]*:%d+:')
      or line:match('^Missing character:')
      or line:match('^LaTeX Warning:')
      or line:match('^LaTeX Info:')
      or line:match('^LaTeX Font Warning:')
      or line:match('^Overfull')
      or line:match('^Underfull')
      or line:match('^Package%s+%S+%s+Warning:')
      or line:match('^Package%s+%S+%s+Info:')
      or line:match('^Class%s+%S+%s+Warning:')
      or line:match('^Class%s+%S+%s+Info:')
      or false
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
      -- The line number is already a column of its own in the quickfix list.
      if item.lnum and item.lnum > 0 then
        item.text = item.text:gsub('%s*on input line %d+%.?$', '')
      end
      item.type = severity(item.text, item.type)
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

    -- Warnings and infos. They may continue on following lines until a blank
    -- line, and the interesting `on input line N` part is often on the
    -- continuation. `severity` sorts the two apart afterwards.
    local warning = line:match('^(LaTeX Warning:%s*.+)$')
      or line:match('^(LaTeX Info:%s*.+)$')
      or line:match('^(LaTeX Font Warning:%s*.+)$')
      or line:match('^(Package%s+%S+%s+Warning:%s*.+)$')
      or line:match('^(Class%s+%S+%s+Warning:%s*.+)$')
      or line:match('^(Package%s+%S+%s+Info:%s*.+)$')
      or line:match('^(Class%s+%S+%s+Info:%s*.+)$')
      or line:match('^(Missing character:%s*.+)$')
    if warning then
      local text = warning
      local j = i + 1
      -- LaTeX either indents a continuation line or prefixes it with the
      -- emitting package in parentheses, as in `(hyperref) ...`. The prefix is
      -- redundant once the lines are joined, so it is stripped. Recognising
      -- these two shapes is what keeps `on input line N`, which usually lands
      -- on the continuation, attached to its message.
      while j <= #lines and j <= i + 4 do
        local raw = lines[j]
        if raw == '' or starts_message(raw) then
          break
        end
        local prefixed = raw:match('^%(%a[%w%-]*%)%s*(.*)$')
        if prefixed then
          text = text .. ' ' .. vim.trim(prefixed)
        elseif raw:match('^%s%s') then
          text = text .. ' ' .. vim.trim(raw)
        else
          break
        end
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

    -- Over/underfull boxes are a typesetting detail rather than a defect, and
    -- they outnumber every other message in a real log, so they are left out
    -- unless `qf.boxes` asks for them. `starts_message` still recognises them
    -- either way, so a box line always terminates the warning above it.
    local is_box = line:match('^Overfull \\[hv]box') or line:match('^Underfull \\[hv]box')
    if is_box and not config.get('qf', 'boxes') then
      update_stack(line, stack, root)
      i = i + 1
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
    if not kind then
      -- `... has occurred while \output is active` carries no line number.
      kind = line:match('^(Overfull \\[hv]box .*)$') or line:match('^(Underfull \\[hv]box .*)$')
      box_lnum = 0
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

--- Collect all diagnostics for `project`, at every severity.
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

--- Split `items` into those the current level shows and those it hides,
--- errors first so that the interesting entries are at the top of the list.
---@param items table[]
---@return table[] shown, integer hidden
local function apply_level(items)
  local max_rank = LEVEL_RANK[M.level()]
  local shown = {}
  local hidden = 0
  for _, item in ipairs(items) do
    if (RANK[item.type] or RANK.W) <= max_rank then
      shown[#shown + 1] = item
    else
      hidden = hidden + 1
    end
  end
  -- `table.sort` is not stable, so carry the original order explicitly.
  for index, item in ipairs(shown) do
    item._index = index
  end
  table.sort(shown, function(a, b)
    local ra, rb = RANK[a.type] or RANK.W, RANK[b.type] or RANK.W
    if ra ~= rb then
      return ra < rb
    end
    return a._index < b._index
  end)
  for _, item in ipairs(shown) do
    item._index = nil
  end
  return shown, hidden
end

--- Fill the quickfix list from `project`'s log and open it if configured.
---@param project table
---@param opts table|nil `{ force_open = boolean, silent = boolean }`
---@return integer errors, integer warnings, integer infos
function M.update(project, opts)
  opts = opts or {}
  if not config.get('qf', 'enabled') then
    return 0, 0, 0
  end

  local all = M.collect(project)
  local items, hidden = apply_level(all)

  local errors, warnings, infos = 0, 0, 0
  for _, item in ipairs(all) do
    if item.type == 'E' then
      errors = errors + 1
    elseif item.type == 'I' then
      infos = infos + 1
    else
      warnings = warnings + 1
    end
  end

  local title = ('nvim-tex: %s [%s]'):format(vim.fn.fnamemodify(project.main, ':t'), M.level())
  if hidden > 0 then
    title = title .. (' (%d hidden)'):format(hidden)
  end
  vim.fn.setqflist({}, ' ', { title = title, items = items })

  project.qf_items = items
  project.qf_errors, project.qf_warnings, project.qf_infos = errors, warnings, infos
  project.qf_hidden = hidden

  local should_open = opts.force_open
    or (config.get('qf', 'auto_open') and (errors > 0 or (warnings > 0 and config.get('qf', 'open_on_warning'))))

  if should_open then
    M.open({ silent = opts.silent, hidden = hidden })
  elseif config.get('qf', 'auto_close') and #items == 0 then
    M.close()
  end

  return errors, warnings, infos
end

---@param opts table|nil `{ silent = boolean, hidden = integer }`
function M.open(opts)
  opts = opts or {}
  local items = vim.fn.getqflist()
  if #items == 0 then
    local hidden = opts.hidden or 0
    if hidden > 0 then
      util.info(('No entries at level %q (%d hidden, :TexQfLevel to show more)'):format(M.level(), hidden))
    else
      util.info('No errors or warnings')
    end
    return
  end

  local winid = vim.api.nvim_get_current_win()
  vim.cmd('botright copen ' .. (config.get('qf', 'height') or 8))
  if config.get('qf', 'autojump') then
    vim.cmd('cfirst')
  elseif opts.silent ~= false then
    vim.api.nvim_set_current_win(winid)
  end
end

function M.close()
  vim.cmd('cclose')
end

return M
