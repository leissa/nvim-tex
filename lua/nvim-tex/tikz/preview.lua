--- `:TexTikzPreview`: compile the picture under the cursor on its own.
---
--- The picture is set in the document it belongs to, cut down to the picture:
---
---   - the preamble of the main file, as it is in its buffer, so the class,
---     fonts, packages and macros are all there;
---   - the `preview` package, which crops the page to the picture
---     (`standalone` documents already do that);
---   - the definitions in the body before the picture: `\newcommand`, `\def`,
---     and the commands in `tikz.preview.commands` such as `\tikzset`;
---   - the main document's `.aux`, so `\ref` and `\cite` resolve.
---
--- The document is compiled from the project root, like the main file, in a
--- throwaway project that keeps its viewer between runs: previewing again
--- recompiles, and the viewer reloads the PDF, or the picture pops up in a
--- floating window (`view.snacks`).
local compiler = require('nvim-tex.compiler')
local config = require('nvim-tex.config')
local tikz = require('nvim-tex.tikz')
local ts = require('nvim-tex.ts')
local util = require('nvim-tex.util')

local M = {}

--- The outermost picture around the cursor.
---@param bufnr integer
---@return TSNode|nil
local function picture_at_cursor(bufnr)
  local picture = tikz.picture(ts.node_at_cursor(bufnr), bufnr)
  while picture do
    local outer = tikz.picture(picture:parent(), bufnr)
    if not outer then
      return picture
    end
    picture = outer
  end
  return nil
end

--- The text of `node`, or from `(srow, scol)` to its end.
---@param node TSNode
---@param bufnr integer
---@param srow integer|nil
---@param scol integer|nil
---@return string
local function text_of(node, bufnr, srow, scol)
  local sr, sc, er, ec = node:range()
  return table.concat(vim.api.nvim_buf_get_text(bufnr, srow or sr, scol or sc, er, ec, {}), '\n')
end

--- Is `node` a definition the picture may rely on?
---@param node TSNode
---@param bufnr integer
---@param commands table<string, boolean>
---@return boolean
local function is_definition(node, bufnr, commands)
  local t = node:type()
  if t == 'generic_command' then
    local name = ts.child_of_type(node, 'command_name')
    return name ~= nil and commands[vim.treesitter.get_node_text(name, bufnr):sub(2)] == true
  end
  return (t:match('_definition$') ~= nil and t ~= 'label_definition') or t:match('_import$') ~= nil
end

--- The source of a definition. `\def\x` leaves its body `{...}` to the next
--- node, and `\tikzstyle{a}` its `=[...]` to the rest of the line.
---@param node TSNode
---@param bufnr integer
---@return string
local function definition_text(node, bufnr)
  local text = text_of(node, bufnr)
  local sibling = node:next_named_sibling()
  if node:type() == 'old_command_definition' and sibling and sibling:type() == 'curly_group' then
    local _, _, er, ec = node:range()
    text = text .. text_of(sibling, bufnr, er, ec)
  end
  local _, _, er, ec = node:range()
  local rest = vim.api.nvim_buf_get_lines(bufnr, er, er + 1, false)[1] or ''
  local options = rest:sub(ec + 1):match('^%s*=%s*%b[]')
  if options then
    text = text .. options
  end
  return text
end

--- The definitions in `bufnr` before `picture`, outside other pictures. In a
--- buffer with a `document` environment only those in its body: the preamble
--- comes with the main file.
---@param bufnr integer
---@param picture TSNode
---@return string[]
function M.definitions(bufnr, picture)
  local root = ts.root(bufnr)
  if not root then
    return {}
  end
  local commands = {}
  for _, name in ipairs(config.get('tikz', 'preview', 'commands') or {}) do
    commands[name] = true
  end
  local document = ts.collect(bufnr, function(node)
    return ts.ENVIRONMENT[node:type()] and ts.env_name(node, bufnr) == 'document'
  end)[1]
  local stop = { picture:start() }

  local out = {}
  local function walk(node)
    for child in node:iter_children() do
      local row, col = child:start()
      if row > stop[1] or (row == stop[1] and col >= stop[2]) then
        return false
      end
      if child:named() and not ts.COMMENT[child:type()] and not ts.VERBATIM[child:type()] then
        if is_definition(child, bufnr, commands) then
          out[#out + 1] = definition_text(child, bufnr)
        elseif not tikz.is_picture(child, bufnr) and walk(child) == false then
          return false
        end
      end
    end
  end
  walk(document or root)
  return out
end

--- The lines of `path`, from its buffer when it is loaded.
---@param path string
---@return string[]
local function lines_of(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end
  return util.readlines(path)
end

--- The preview document for `picture`.
---@param project table
---@param bufnr integer
---@param picture TSNode
---@return string[]|nil lines, string|nil error
function M.document(project, bufnr, picture)
  local preamble = {}
  local found = false
  for _, line in ipairs(lines_of(project.main)) do
    if line:match('\\begin%s*{document}') then
      found = true
      break
    end
    preamble[#preamble + 1] = line
  end
  if not found then
    return nil, 'no \\begin{document} in ' .. vim.fn.fnamemodify(project.main, ':~:.')
  end

  local opts = config.get('tikz', 'preview')
  local document = preamble
  local standalone = table.concat(preamble, '\n'):match('\\documentclass%s*%b[]%s*{%s*standalone%s*}')
    or table.concat(preamble, '\n'):match('\\documentclass%s*{%s*standalone%s*}')
  if not standalone then
    vim.list_extend(document, {
      '\\makeatletter',
      '\\@ifpackageloaded{preview}{}{\\usepackage[active,tightpage]{preview}}',
      '\\makeatother',
      '\\PreviewEnvironment{' .. ts.env_name(picture, bufnr) .. '}',
      '\\setlength\\PreviewBorder{' .. opts.border .. '}',
    })
  end
  vim.list_extend(document, M.definitions(bufnr, picture))
  local aux = util.join(project.aux_dir, project.name .. '.aux')
  if opts.aux and util.is_file(aux) then
    -- Read where LaTeX reads its own `.aux`: `\\newlabel` and friends are
    -- no longer allowed once `\\begin{document}` is done.
    document[#document + 1] = '\\makeatletter\\AtBeginDocument{\\makeatletter\\@input{'
      .. aux
      .. '}\\makeatother}\\makeatother'
  end
  document[#document + 1] = '\\begin{document}'
  vim.list_extend(document, vim.split(text_of(picture, bufnr), '\n', { plain = true }))
  document[#document + 1] = '\\end{document}'
  return document
end

--- Compile the picture under the cursor and show it.
---@param project table
function M.preview(project)
  local bufnr = vim.api.nvim_get_current_buf()
  local picture = picture_at_cursor(bufnr)
  if not picture then
    util.warn('not in a TikZ picture')
    return
  end
  local document, err = M.document(project, bufnr, picture)
  if not document then
    util.error(err)
    return
  end
  compiler.compile_fragment(project, 'tikz-preview', document, require('nvim-tex.viewer').show_fragment)
end

return M
