--- `:TexCite`: search an online bibliography, append the chosen entry to the
--- project's bibliography and cite it.
---
--- The flow is asynchronous from end to end: the search prompt, the result
--- list and the key prompt go through `vim.ui.input`/`vim.ui.select`, so a
--- picker plugin that overrides them takes over. The insertion point is
--- tracked with an extmark while the user makes up their mind.
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = {}

--- Available sources, by the name of their `cite` option table.
M.sources = {
  dblp = require('nvim-tex.cite.dblp'),
}

--- Search order.
local ORDER = { 'dblp' }

local ns = vim.api.nvim_create_namespace('nvim-tex-cite')

--- The enabled sources, in search order.
---@return table[]
function M.enabled_sources()
  local out = {}
  for _, name in ipairs(ORDER) do
    if config.get('cite', name, 'enabled') then
      out[#out + 1] = M.sources[name]
    end
  end
  return out
end

--- Drop the `%` comments of a line, keeping `\%`.
---@param line string
---@return string
local function strip_comment(line)
  return (line:gsub('^(.-[^\\])%%.*$', '%1'):gsub('^%%.*$', ''))
end

--- The bibliography files named in `lines`, in order: `\addbibresource{a.bib}`
--- (biblatex) and `\bibliography{a,b}` (BibTeX, without the extension).
---@param lines string[]
---@return string[]
function M.bib_resources(lines)
  local found = {}
  for _, line in ipairs(lines) do
    line = strip_comment(line)
    local pos = 1
    while true do
      local s, e, cmd, arg = line:find('\\(%a+)%s*%b[]%s*(%b{})', pos)
      local s2, e2, cmd2, arg2 = line:find('\\(%a+)%s*(%b{})', pos)
      if s2 and (not s or s2 < s) then
        s, e, cmd, arg = s2, e2, cmd2, arg2
      end
      if not s then
        break
      end
      if cmd == 'addbibresource' or cmd == 'addglobalbib' then
        found[#found + 1] = vim.trim(arg:sub(2, -2))
      elseif cmd == 'bibliography' then
        for name in arg:sub(2, -2):gmatch('[^,]+') do
          name = vim.trim(name)
          found[#found + 1] = name:match('%.bib$') and name or (name .. '.bib')
        end
      end
      pos = e + 1
    end
  end
  return found
end

--- The bibliography new entries go to: the first one the main file names,
--- else the first `.bib` file under the project root.
---@param project table
---@return string|nil
function M.bib_file(project)
  local names = M.bib_resources(util.readlines(project.main))
  local name = names[1]
  if name then
    if name:match('^[/~]') then
      return util.normalize(name)
    end
    return util.normalize(util.join(project.root, name))
  end
  local bibs = vim.fn.globpath(project.root, '**/*.bib', false, true)
  table.sort(bibs)
  return bibs[1] and util.normalize(bibs[1]) or nil
end

--- The lines of `path`, from its buffer when it is loaded.
---@param path string
---@return string[], integer|nil bufnr
local function bib_lines(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), bufnr
  end
  return util.readlines(path), nil
end

--- The entries of a `.bib` file as `{ key, doi, biburl }`, found line by line:
--- enough for the files people write and the entries this module appends.
---@param lines string[]
---@return table[]
function M.bib_entries(lines)
  local entries = {}
  local current
  for _, line in ipairs(lines) do
    local key = line:match('^%s*@%a+%s*[{(]%s*([^,%s]+)%s*,')
    if key then
      current = { key = key }
      entries[#entries + 1] = current
    elseif current then
      local field, value = line:match('^%s*(%a+)%s*=%s*[{"]?%s*([^}"]*)')
      if field then
        field = field:lower()
        if field == 'doi' or field == 'biburl' then
          current[field] = vim.trim(value):gsub(',$', ''):lower()
        end
      end
    end
  end
  return entries
end

--- The key under which `entry` is already in the bibliography, if it is.
---@param entries table[]
---@param entry table
---@return string|nil
function M.existing_key(entries, entry)
  for _, existing in ipairs(entries) do
    if existing.key == entry.source_key then
      return existing.key
    end
    if entry.biburl and existing.biburl == entry.biburl:lower() then
      return existing.key
    end
    if entry.doi and existing.doi == entry.doi:lower() then
      return existing.key
    end
  end
  return nil
end

--- Accented Latin letters, as they come out of DBLP, and what a key makes of
--- them.
local FOLD = {
  ['ß'] = 'ss',
  ['æ'] = 'ae',
  ['œ'] = 'oe',
  ['ø'] = 'o',
  ['ł'] = 'l',
  ['đ'] = 'd',
  ['ð'] = 'd',
  ['þ'] = 'th',
  ['ı'] = 'i',
}
for base, accented in pairs({
  a = 'àáâãäåāăą',
  c = 'çćĉċč',
  d = 'ď',
  e = 'èéêëēĕėęě',
  g = 'ĝğġģ',
  h = 'ĥ',
  i = 'ìíîïĩīĭį',
  j = 'ĵ',
  k = 'ķ',
  l = 'ĺļľ',
  n = 'ñńņňŉ',
  o = 'òóôõöōŏő',
  r = 'ŕŗř',
  s = 'śŝşšș',
  t = 'ţťț',
  u = 'ùúûüũūŭůűų',
  w = 'ŵ',
  y = 'ýÿŷ',
  z = 'źżž',
}) do
  for _, char in ipairs(vim.fn.split(accented, '\\zs')) do
    FOLD[char] = base
  end
end

--- Lower-case ASCII letters and digits only: `Leißa` -> `leissa`.
---@param s string
---@return string
function M.ascii(s)
  local out = {}
  for _, char in ipairs(vim.fn.split(vim.fn.tolower(s), '\\zs')) do
    out[#out + 1] = FOLD[char] or char
  end
  return (table.concat(out):gsub('[^a-z0-9]', ''))
end

--- Words that do not make a key.
local SKIP = {}
for word in ('a an and are as at by for from how in is of on the to towards via what when why with'):gmatch('%a+') do
  SKIP[word] = true
end

--- `leissa2015graph`: the first author's last name, the year and the first
--- word of the title that says something.
---@param entry table
---@return string
function M.short_key(entry)
  local name = entry.authors[1] or entry.editors[1] or ''
  local last = M.ascii(name:match('(%S+)%s*$') or name)
  local word = ''
  for token in (entry.title or ''):gmatch('[^%s%-/:,.;!?()]+') do
    local folded = M.ascii(token)
    if folded ~= '' and not SKIP[folded] then
      word = folded
      break
    end
  end
  local key = last .. (entry.year or '') .. word
  return key ~= '' and key or entry.source_key
end

--- The key a new entry gets before the user has a say.
---@param entry table
---@return string
function M.suggest_key(entry)
  local style = config.get('cite', 'key')
  if type(style) == 'function' then
    return style(entry)
  end
  if style == 'source' then
    return entry.source_key
  end
  return M.short_key(entry)
end

--- `key`, or `key` with the first free suffix `b`, `c`, ...
---@param key string
---@param entries table[]
---@return string
function M.unique_key(key, entries)
  local taken = {}
  for _, entry in ipairs(entries) do
    taken[entry.key] = true
  end
  if not taken[key] then
    return key
  end
  for byte = ('b'):byte(), ('z'):byte() do
    local candidate = key .. string.char(byte)
    if not taken[candidate] then
      return candidate
    end
  end
  return key
end

--- Is `key` usable as a citation key?
---@param key string
---@return boolean
function M.valid_key(key)
  return key ~= '' and not key:find('[%s,{}()"#%%\'=\\~]')
end

--- Escape what LaTeX would choke on in a field value. Titles with `$` are
--- left alone: they carry math, and `_` is meant there.
---@param value string
---@return string
local function escape(value)
  value = value:gsub('([&%%#])', '\\%1')
  if not value:find('%$') then
    value = value:gsub('_', '\\_')
  end
  return value
end

--- Does a part of `word` between hyphens and slashes have an upper-case
--- letter after its first character? `AnyDSL`, `GPUs`, `iOS`, but not
--- `High-Performance`.
---@param word string
---@return boolean
local function inner_upper(word)
  for part in word:gmatch('[^%-/]+') do
    if part:gsub('^%p+', ''):sub(2):find('%u') then
      return true
    end
  end
  return false
end

--- Brace the words of a title with upper-case letters inside, so BibTeX
--- styles keep their case.
---@param title string
---@return string
local function protect(title)
  return (
    title:gsub('%S+', function(word)
      if inner_upper(word) and not word:find('[{}\\$]') then
        local lead, core, trail = word:match('^(%p*)(.-)(%p*)$')
        return lead .. '{' .. core .. '}' .. trail
      end
      return word
    end)
  )
end

local VERBATIM = { url = true, doi = true, biburl = true, eprint = true, isbn = true }

--- The lines of the BibTeX entry.
---@param entry table
---@param key string
---@return string[]
function M.format(entry, key)
  local lines = { ('@%s{%s,'):format(entry.type, key) }
  local width = 0
  for _, field in ipairs(entry.fields) do
    width = math.max(width, #field[1])
  end
  for i, field in ipairs(entry.fields) do
    local name, value = field[1], field[2]
    if not VERBATIM[name] then
      value = escape(value)
      if name == 'title' or name == 'booktitle' then
        value = protect(value)
      end
    end
    local sep = i < #entry.fields and ',' or ''
    lines[#lines + 1] = ('  %s = {%s}%s'):format(name .. (' '):rep(width - #name), value, sep)
  end
  lines[#lines + 1] = '}'
  return lines
end

--- Append `entry_lines` to `path`, through its buffer when it is loaded. A
--- buffer without other changes is written; one with changes is left for the
--- user to save.
---@param path string
---@param entry_lines string[]
---@return boolean written
function M.append(path, entry_lines)
  local lines, bufnr = bib_lines(path)
  local block = vim.deepcopy(entry_lines)
  if #lines > 0 and lines[#lines] ~= '' then
    table.insert(block, 1, '')
  end
  if bufnr then
    local modified = vim.bo[bufnr].modified
    local empty = #lines == 1 and lines[1] == ''
    vim.api.nvim_buf_set_lines(bufnr, empty and 0 or -1, -1, false, empty and entry_lines or block)
    if modified then
      return false
    end
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd('silent write')
    end)
    return true
  end
  vim.list_extend(lines, block)
  util.writelines(path, lines)
  return true
end

--- What to insert for `key` at byte column `col` of `line`, and where the
--- cursor goes, as a byte offset into that text. Inside the braces of a
--- `\cite`-like command the key joins the list and the cursor stays behind
--- it; anywhere else it comes with its own `\cite{}` and the cursor goes
--- behind that.
---@param line string
---@param col integer
---@param key string
---@return string text, integer cursor
function M.insertion(line, col, key)
  local before, after = line:sub(1, col), line:sub(col + 1)
  local open
  local depth = 0
  for i = #before, 1, -1 do
    local char = before:sub(i, i)
    if char == '}' then
      depth = depth + 1
    elseif char == '{' then
      if depth == 0 then
        open = i
        break
      end
      depth = depth - 1
    end
  end

  if open then
    local cmd = before:sub(1, open - 1)
    repeat
      local stripped = cmd:gsub('%s*%b[]%s*$', '')
      local changed = stripped ~= cmd
      cmd = stripped
    until not changed
    if cmd:match('\\%a*[cC]ite%a*%*?$') then
      local inner = before:sub(open + 1)
      local text = key
      if not (inner:match('^%s*$') or inner:match(',%s*$')) then
        text = ',' .. text
      end
      local cursor = #text
      if after:match('^%s*[^%s,}]') then
        text = text .. ','
      end
      return text, cursor
    end
  end
  local text = '\\cite{' .. key .. '}'
  return text, #text
end

--- Insert `key` at the extmark `mark` of `bufnr`, and put the cursor behind
--- it -- back in insert mode if that is where `:TexCite` was started.
---@param bufnr integer
---@param mark integer
---@param key string
---@param insert_mode boolean
function M.insert_key(bufnr, mark, key, insert_mode)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, mark, {})
  vim.api.nvim_buf_del_extmark(bufnr, ns, mark)
  if not pos[1] then
    return
  end
  local row, col = pos[1], pos[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local text, cursor = M.insertion(line, col, key)
  vim.api.nvim_buf_set_text(bufnr, row, col, row, col, { text })

  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end
  vim.api.nvim_set_current_win(win)
  if insert_mode then
    -- Normal mode cannot hold the cursor behind the last character, which is
    -- where `startinsert!` puts it.
    if col + cursor >= #line + #text then
      vim.cmd('startinsert!')
    else
      vim.api.nvim_win_set_cursor(win, { row + 1, col + cursor })
      vim.cmd('startinsert')
    end
  else
    vim.api.nvim_win_set_cursor(win, { row + 1, math.max(col + cursor - 1, 0) })
  end
end

--- One line of the result list.
---@param item table
---@return string
function M.format_item(item)
  local names = vim.tbl_map(function(name)
    return name:match('(%S+)%s*$') or name
  end, vim.list_slice(item.authors, 1, 3))
  local authors = table.concat(names, ', ') .. (#item.authors > 3 and ' et al.' or '')
  local parts = { item.title }
  if authors ~= '' then
    table.insert(parts, 1, authors)
  end
  if item.venue then
    parts[#parts + 1] = item.venue
  end
  if item.year then
    parts[#parts + 1] = item.year
  end
  return table.concat(parts, ' · ')
end

--- Search all enabled sources, one after the other, and collect the results.
---@param sources table[]
---@param query string
---@param done fun(items: table[])
local function search(sources, query, done)
  local items = {}
  local function step(i)
    local source = sources[i]
    if not source then
      done(items)
      return
    end
    source.search(query, function(err, found)
      if err then
        util.error(('%s search failed: %s'):format(source.name, err))
      else
        vim.list_extend(items, found)
      end
      step(i + 1)
    end)
  end
  step(1)
end

--- Ask for the key, starting from `key`, until it is usable and free.
---@param key string
---@param entries table[]
---@param done fun(key: string)
local function ask_key(key, entries, done)
  vim.ui.input({ prompt = 'Citation key: ', default = key }, function(input)
    if input == nil then
      return
    end
    input = vim.trim(input)
    if not M.valid_key(input) then
      util.warn(('invalid citation key: %q'):format(input))
      ask_key(key, entries, done)
      return
    end
    for _, existing in ipairs(entries) do
      if existing.key == input then
        util.warn(input .. ' is already taken')
        ask_key(M.unique_key(input, entries), entries, done)
        return
      end
    end
    done(input)
  end)
end

--- `:TexCite [query]`.
---@param project table
---@param query string|nil
function M.cite(project, query)
  local sources = M.enabled_sources()
  if #sources == 0 then
    util.error('no citation source is enabled (cite.dblp.enabled)')
    return
  end
  local bib = M.bib_file(project)
  if not bib then
    util.error('no bibliography: add \\addbibresource{refs.bib} or \\bibliography{refs} to ' .. project.main)
    return
  end

  -- Where the key goes: at the cursor in insert mode; in normal mode behind
  -- the character under the cursor, unless that closes a group -- the key
  -- belongs into `\cite{a}` with the cursor on its `}`.
  local bufnr = vim.api.nvim_get_current_buf()
  local insert_mode = vim.api.nvim_get_mode().mode:sub(1, 1) == 'i'
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local line = vim.api.nvim_get_current_line()
  if not insert_mode and #line > 0 and line:sub(col + 1, col + 1) ~= '}' then
    col = col + vim.str_utf_end(line, col + 1) + 1
  end
  local mark = vim.api.nvim_buf_set_extmark(bufnr, ns, row, col, { right_gravity = false })
  local function cancel()
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark)
  end

  local function chosen(item)
    if not item then
      cancel()
      return
    end
    item.source.entry(item, function(err, entry)
      if err then
        cancel()
        util.error(('%s: %s'):format(item.source.name, err))
        return
      end
      local lines = bib_lines(bib)
      local entries = M.bib_entries(lines)
      local existing = M.existing_key(entries, entry)
      if existing then
        util.info(('already in %s as %s'):format(vim.fn.fnamemodify(bib, ':t'), existing))
        M.insert_key(bufnr, mark, existing, insert_mode)
        return
      end
      local function commit(key)
        local written = M.append(bib, M.format(entry, key))
        M.insert_key(bufnr, mark, key, insert_mode)
        local where = vim.fn.fnamemodify(bib, ':~:.')
        util.info(written and ('added %s to %s'):format(key, where) or ('added %s to %s (unsaved)'):format(key, where))
      end
      local key = M.unique_key(M.suggest_key(entry), entries)
      if config.get('cite', 'edit_key') then
        ask_key(key, entries, commit)
      else
        commit(key)
      end
    end)
  end

  local function run(q)
    if not q or vim.trim(q) == '' then
      cancel()
      return
    end
    util.info(('searching %s for "%s"'):format(
      table.concat(
        vim.tbl_map(function(s)
          return s.name
        end, sources),
        ', '
      ),
      q
    ))
    search(sources, q, function(items)
      if #items == 0 then
        cancel()
        util.warn(('nothing found for "%s"'):format(q))
        return
      end
      vim.ui.select(items, {
        prompt = 'Cite',
        kind = 'nvim-tex.cite',
        format_item = M.format_item,
      }, chosen)
    end)
  end

  if query and vim.trim(query) ~= '' then
    run(query)
  else
    vim.ui.input({ prompt = 'Search: ' }, run)
  end
end

return M
