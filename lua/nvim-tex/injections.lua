--- Code highlighting inside `lstlisting`.
---
--- nvim-treesitter's injection query already covers `minted`, `pycode`,
--- `luacode` and friends, whose language is in the environment name or its
--- first argument. `lstlisting` gives it in its options, which the parser
--- leaves as part of the code: `queries/latex/injections.scm` adds a pattern
--- for it, and this directive works out the language. The query file is found
--- on the runtimepath whether or not nvim-tex is set up, so the directive is
--- registered as soon as the plugin loads.
local ts = require('nvim-tex.ts')

local M = {}

--- listings' names for languages whose parser is called something else. Any
--- other name is used as it is, lower-cased.
M.ALIASES = {
  ['c++'] = 'cpp',
  ['c#'] = 'c_sharp',
  ['tex'] = 'latex',
  ['sh'] = 'bash',
  ['octave'] = 'matlab',
}

--- The language named in a listings option list, e.g. `[language=Python]`,
--- `[language={[Sharp]C}]` or `[style=x, language=C++]`, and the length of
--- the option list.
---@param code string
---@return string|nil language, integer|nil length
function M.parse_options(code)
  local options, stop = code:match('^%s*(%b[])()')
  if not options then
    return nil, nil
  end
  local length = stop - 1
  local value = options:match('[%[,]%s*language%s*=%s*(%b{})') or options:match('[%[,]%s*language%s*=%s*([^,%]]+)')
  if not value then
    return nil, length
  end
  -- `{[Objective]Caml}`: the dialect in brackets is dropped.
  value = vim.trim(value:gsub('^{(.*)}$', '%1'):gsub('%b[]', '')):lower()
  if value == '' then
    return nil, length
  end
  return M.ALIASES[value] or value, length
end

local registered = false

function M.register()
  if registered then
    return
  end
  registered = true
  vim.treesitter.query.add_directive('nvim-tex-lstlisting!', function(match, _, source, predicate, metadata)
    local id = predicate[2]
    local node = ts.captured(match, id)
    if not node then
      return
    end
    local code = vim.treesitter.get_node_text(node, source)
    local lang, length = M.parse_options(code)
    if not lang then
      return
    end
    metadata['injection.language'] = lang
    -- Start the code after the option list.
    local srow, scol, erow, ecol = node:range()
    local options = code:sub(1, length)
    local newlines = select(2, options:gsub('\n', ''))
    local last = options:match('[^\n]*$')
    local col = newlines > 0 and #last or scol + #last
    ts.set_range(metadata, id, { srow + newlines, col, erow, ecol })
  end, ts.HANDLER_OPTS)
end

return M
