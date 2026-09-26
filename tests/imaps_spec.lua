local H = require('tests.helpers')
local config = require('nvim-tex.config')
local imaps = require('nvim-tex.imaps')

--- The typed sequences of the insert mappings `imaps` created in `bufnr`.
--- Filtered by description, because the plugin sets other insert mappings too.
---@param bufnr integer
---@return string[]
local function imap_lhss(bufnr)
  local out = {}
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'i')) do
    if tostring(map.desc):match('^nvim%-tex: imap') then
      out[#out + 1] = map.lhs
    end
  end
  return out
end

--- Type `keys` in insert mode at the cursor and return the resulting line.
---@param keys string
---@return string
local function type_keys(keys)
  vim.api.nvim_feedkeys('i' .. keys, 'x', false)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)
  return vim.api.nvim_get_current_line()
end

describe('imaps', function()
  after_each(H.cleanup)

  describe('lhs', function()
    it('prefixes the configured leader', function()
      T.eq('`a', imaps.lhs({ lhs = 'a', rhs = '\\alpha' }))
    end)

    it('honours a per-entry leader', function()
      T.eq('#b', imaps.lhs({ leader = '#', lhs = 'b', style = 'mathbf' }))
    end)

    it('follows a changed leader', function()
      config.setup({ imaps = { leader = ';' } })
      T.eq(';a', imaps.lhs({ lhs = 'a', rhs = '\\alpha' }))
    end)
  end)

  describe('rhs_label', function()
    it('shows the text of a plain entry', function()
      T.eq('\\alpha', imaps.rhs_label({ lhs = 'a', rhs = '\\alpha' }))
    end)

    it('shows the shape of a style entry', function()
      T.eq('\\mathbf{<char>}', imaps.rhs_label({ lhs = 'b', style = 'mathbf' }))
    end)

    it('says so for a function', function()
      T.eq('<function>', imaps.rhs_label({ lhs = 'x', rhs = function() return 'x' end }))
    end)
  end)

  describe('entries', function()
    it('returns the configured list', function()
      config.setup({ imaps = { list = { { lhs = 'a', rhs = '\\alpha' }, { lhs = 'b', rhs = '\\beta' } } } })
      T.eq(2, #imaps.entries())
    end)

    it('leaves the disabled ones out', function()
      config.setup({
        imaps = {
          list = { { lhs = 'a', rhs = '\\alpha' }, { lhs = 'b', rhs = '\\beta' } },
          disabled = { 'a' },
        },
      })
      local entries = imaps.entries()
      T.eq(1, #entries)
      T.eq('b', entries[1].lhs)
    end)

    it('includes what add registered', function()
      config.setup({ imaps = { list = {} } })
      imaps.add({ lhs = 'oo', rhs = '\\circ' })
      local entries = imaps.entries()
      T.eq(1, #entries)
      T.eq('\\circ', entries[1].rhs)
    end)

    it('has no duplicate lhs in the shipped list', function()
      local seen = {}
      for _, entry in ipairs(config.defaults.imaps.list) do
        local key = imaps.lhs(entry)
        T.falsy(seen[key], ('duplicate mapping %s'):format(key))
        seen[key] = true
      end
    end)
  end)

  describe('wrappers', function()
    it("expands unconditionally for 'trivial'", function()
      T.eq('x', imaps.wrappers.trivial('`t', function() return 'x' end))
    end)

    it("expands only inside math for 'math'", function()
      H.buf({ 'text $x$ text' })
      H.cursor(1, 6) -- inside the formula
      T.eq('\\alpha', imaps.wrappers.math('`a', function() return '\\alpha' end))
      H.cursor(1, 1) -- in the prose
      T.eq('`a', imaps.wrappers.math('`a', function() return '\\alpha' end))
    end)
  end)

  describe('attached mappings', function()
    before_each(function()
      config.setup({
        imaps = { list = { { lhs = 'a', rhs = '\\alpha' }, { lhs = '`', rhs = '``', wrapper = 'trivial' } } },
      })
    end)

    it('creates a buffer-local insert mapping per entry', function()
      local bufnr = H.buf({ 'text' })
      imaps.attach(bufnr)
      local lhss = imap_lhss(bufnr)
      table.sort(lhss)
      local expected = vim.tbl_map(function(entry)
        return imaps.lhs(entry)
      end, imaps.entries())
      table.sort(expected)
      T.eq(expected, lhss)
      T.contains(lhss, '`a')
      T.contains(lhss, '``')
    end)

    it('creates nothing when imaps are disabled', function()
      config.setup({ imaps = { enabled = false } })
      local bufnr = H.buf({ 'text' })
      imaps.attach(bufnr)
      T.eq(0, #imap_lhss(bufnr))
    end)

    it('expands inside a formula', function()
      H.need_parser()
      local bufnr = H.buf({ 'text $$ text' })
      imaps.attach(bufnr)
      H.cursor(1, 6)
      T.eq('text $\\alpha$ text', type_keys('`a'))
    end)

    it('leaves the prose alone', function()
      H.need_parser()
      local bufnr = H.buf({ 'text  text' })
      imaps.attach(bufnr)
      H.cursor(1, 5)
      T.eq('text `a text', type_keys('`a'))
    end)

    it('inserts a LaTeX quotation for the leader typed twice', function()
      H.need_parser()
      local bufnr = H.buf({ 'say  here' })
      imaps.attach(bufnr)
      H.cursor(1, 4)
      T.eq('say `` here', type_keys('``'))
    end)

    it('reaches buffers that were attached before the entry was added', function()
      local bufnr = H.buf({ 'text' })
      imaps.attach(bufnr)
      imaps.add({ lhs = 'oo', rhs = '\\circ' })
      T.contains(imap_lhss(bufnr), '`oo')
    end)
  end)
end)
