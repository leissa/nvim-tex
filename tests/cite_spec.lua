local H = require('tests.helpers')
local cite = require('nvim-tex.cite')
local config = require('nvim-tex.config')
local dblp = require('nvim-tex.cite.dblp')

local REC = 'https://dblp.org/rec/conf/cgo/LeissaKH15'
local SCHEMA = 'https://dblp.org/rdf/schema#'

--- A SPARQL JSON result with `rows`, all values literals.
---@param rows table[]
---@return table
local function result(rows)
  local bindings = {}
  for _, row in ipairs(rows) do
    local binding = {}
    for var, value in pairs(row) do
      binding[var] = { type = 'literal', value = value }
    end
    bindings[#bindings + 1] = binding
  end
  return { results = { bindings = bindings } }
end

--- The rows of the entry query for LeissaKH15, as DBLP returns them.
local ENTRY_ROWS = {
  { k = 'pub', p = SCHEMA .. 'bibtexType', o = 'http://purl.org/net/nknouf/ns/bibtex#Inproceedings' },
  { k = 'pub', p = SCHEMA .. 'title', o = 'A graph-based higher-order intermediate representation.' },
  { k = 'pub', p = SCHEMA .. 'pagination', o = '202-212' },
  { k = 'pub', p = SCHEMA .. 'yearOfPublication', o = '2015' },
  { k = 'pub', p = SCHEMA .. 'doi', o = 'https://doi.org/10.1109/CGO.2015.7054200' },
  { k = 'pub', p = SCHEMA .. 'primaryDocumentPage', o = 'https://doi.org/10.1109/CGO.2015.7054200' },
  { k = 'pub', p = SCHEMA .. 'publishedInBook', o = 'CGO' },
  { k = 'author', p = '3', o = 'Sebastian Hack' },
  { k = 'author', p = '1', o = 'Roland Leißa' },
  { k = 'author', p = '2', o = 'Marcel Köster 0001' },
  { k = 'book', p = SCHEMA .. 'title', o = 'Proceedings of the 13th CGO 2015' },
  { k = 'book', p = SCHEMA .. 'publishedBy', o = 'IEEE Computer Society' },
}

--- Answer the queries `dblp` sends with canned results, by their shape.
local function fake_dblp()
  dblp.post = function(query, done)
    if query:find('ORDER BY', 1, true) then
      done(
        nil,
        result({ { pub = REC, title = 'A graph-based higher-order intermediate representation.', year = '2015' } })
      )
    elseif query:find('?k ?p ?o', 1, true) then
      done(nil, result(ENTRY_ROWS))
    else
      done(
        nil,
        result({
          { pub = REC, type = 'http://purl.org/net/nknouf/ns/bibtex#Inproceedings', venue = 'CGO' },
          { pub = REC, ord = '2', name = 'Marcel Köster' },
          { pub = REC, ord = '1', name = 'Roland Leißa' },
        })
      )
    end
  end
end

describe('cite', function()
  local post, input, select

  before_each(function()
    post, input, select = dblp.post, vim.ui.input, vim.ui.select
  end)

  after_each(function()
    dblp.post, vim.ui.input, vim.ui.select = post, input, select
    H.cleanup()
  end)

  describe('dblp', function()
    it('splits the query into words that cannot break the SPARQL string', function()
      T.eq({ 'leißa', 'graph', 'based' }, dblp.words('Leißa  "graph-based"\\'))
      T.eq('graph based higher order', dblp.phrase('Graph-based, higher-order.'))
    end)

    it('looks for every word in titles and author names, the last as a prefix', function()
      local query = dblp.search_query('leißa graph', 30)
      T.matches('ql:contains%-word "leißa"', query)
      T.matches('ql:contains%-word "graph%*"', query)
      T.matches('dblp:authoredBy/dblp:primaryCreatorName %?e1', query)
      T.matches('"lei a graph"%) AS %?phrase', query)
      T.matches('LIMIT 30', query)
      T.eq(nil, dblp.search_query(' ,. ', 30))
    end)

    it('orders the authors and drops the homonym numbers', function()
      T.eq({ 'Roland Leißa', 'Wei Wang' }, dblp.ordered_names('2:Wei Wang 0001|1:Roland Leißa'))
    end)

    it('builds the entry from the record, its signatures and its proceedings', function()
      local entry = dblp.build(REC, dblp.group(ENTRY_ROWS))
      T.eq('inproceedings', entry.type)
      T.eq('DBLP:conf/cgo/LeissaKH15', entry.source_key)
      T.eq('10.1109/CGO.2015.7054200', entry.doi)
      local fields = {}
      for _, field in ipairs(entry.fields) do
        fields[field[1]] = field[2]
      end
      T.eq('Roland Leißa and Marcel Köster and Sebastian Hack', fields.author)
      T.eq('A graph-based higher-order intermediate representation', fields.title)
      T.eq('Proceedings of the 13th CGO 2015', fields.booktitle)
      T.eq('202--212', fields.pages)
      T.eq('IEEE Computer Society', fields.publisher)
      T.eq('https://dblp.org/rec/conf/cgo/LeissaKH15.bib', fields.biburl)
    end)

    it('turns an arXiv page into eprint fields', function()
      local entry = dblp.build(
        'https://dblp.org/rec/journals/corr/VaswaniSPUJGKP17',
        dblp.group({
          { k = 'pub', p = SCHEMA .. 'bibtexType', o = 'http://purl.org/net/nknouf/ns/bibtex#Article' },
          { k = 'pub', p = SCHEMA .. 'title', o = 'Attention Is All You Need.' },
          { k = 'pub', p = SCHEMA .. 'publishedInJournal', o = 'CoRR' },
          { k = 'pub', p = SCHEMA .. 'documentPage', o = 'http://arxiv.org/abs/1706.03762' },
        })
      )
      local fields = {}
      for _, field in ipairs(entry.fields) do
        fields[field[1]] = field[2]
      end
      T.eq('CoRR', fields.journal)
      T.eq('arXiv', fields.eprinttype)
      T.eq('1706.03762', fields.eprint)
    end)
  end)

  describe('bibliography', function()
    it('finds the resources named by biblatex and BibTeX, skipping comments', function()
      T.eq(
        { 'refs.bib', 'a.bib', 'b.bib' },
        cite.bib_resources({
          '% \\addbibresource{old.bib}',
          '\\addbibresource[label=x]{refs.bib}',
          '\\bibliography{a, b.bib} % \\bibliography{c}',
        })
      )
    end)

    it('takes the first named file, else the first .bib under the root', function()
      local dir = H.tmpdir()
      local project = H.project(dir .. '/main.tex')
      H.write(dir .. '/z.bib', '')
      H.write(dir .. '/sub/a.bib', '')
      H.write(project.main, { '\\documentclass{article}' })
      T.eq(dir .. '/sub/a.bib', cite.bib_file(project))
      H.write(project.main, { '\\bibliography{lit/refs}' })
      T.eq(dir .. '/lit/refs.bib', cite.bib_file(project))
    end)

    it('recognises an entry that is already there', function()
      local entries = cite.bib_entries({
        '@inproceedings{mine,',
        '  author = {Roland Leißa},',
        '  doi    = {10.1109/cgo.2015.7054200},',
        '}',
        '@article{other, title = {x}}',
      })
      T.eq('mine', cite.existing_key(entries, { source_key = 'DBLP:x', doi = '10.1109/CGO.2015.7054200' }))
      T.eq(nil, cite.existing_key(entries, { source_key = 'DBLP:x', doi = '10.1/other' }))
      T.eq('other', cite.existing_key(entries, { source_key = 'other' }))
    end)
  end)

  describe('keys', function()
    local entry = {
      authors = { 'Roland Leißa' },
      editors = {},
      year = '2015',
      title = 'A graph-based higher-order intermediate representation',
      source_key = 'DBLP:conf/cgo/LeissaKH15',
    }

    it('makes a short key from author, year and title', function()
      T.eq('leissa2015graph', cite.short_key(entry))
      T.eq(
        'muller2020faster',
        cite.short_key({ authors = { 'André Müller' }, editors = {}, year = '2020', title = 'On: Towards Faster X' })
      )
    end)

    it('follows the key option', function()
      config.setup({ cite = { key = 'source' } })
      T.eq('DBLP:conf/cgo/LeissaKH15', cite.suggest_key(entry))
      config.setup({
        cite = {
          key = function(e)
            return 'x' .. e.year
          end,
        },
      })
      T.eq('x2015', cite.suggest_key(entry))
    end)

    it('appends a letter to a taken key', function()
      T.eq('k', cite.unique_key('k', {}))
      T.eq('kc', cite.unique_key('k', { { key = 'k' }, { key = 'kb' } }))
    end)

    it('rejects keys BibTeX cannot take', function()
      T.ok(cite.valid_key('DBLP:conf/cgo/LeissaKH15'))
      T.falsy(cite.valid_key('a b'))
      T.falsy(cite.valid_key('a,b'))
      T.falsy(cite.valid_key(''))
    end)
  end)

  it('formats the entry with escapes and case protection', function()
    local lines = cite.format({
      type = 'article',
      fields = {
        { 'title', 'AnyDSL & High-Performance GPUs: 100% fast' },
        { 'url', 'https://example.org/a_b%20c' },
      },
    }, 'key')
    T.eq({
      '@article{key,',
      '  title = {{AnyDSL} \\& High-Performance {GPUs}: 100\\% fast},',
      '  url   = {https://example.org/a_b%20c}',
      '}',
    }, lines)
  end)

  describe('insertion', function()
    it('adds the key to the cite command it is typed in', function()
      T.eq({ 'k', 1 }, { cite.insertion('\\cite{', 6, 'k') })
      T.eq({ ',k', 2 }, { cite.insertion('\\cite{a}', 7, 'k') })
      T.eq({ 'k', 1 }, { cite.insertion('\\cite{a, }', 9, 'k') })
      T.eq({ 'k,', 1 }, { cite.insertion('\\cite{a}', 6, 'k') })
      T.eq({ 'k', 1 }, { cite.insertion('\\parencite[see][p. 3]{', 22, 'k') })
    end)

    it('brings its own \\cite anywhere else', function()
      T.eq({ '\\cite{k}', 8 }, { cite.insertion('see ', 4, 'k') })
      T.eq({ '\\cite{k}', 8 }, { cite.insertion('\\emph{', 6, 'k') })
    end)
  end)

  describe(':TexCite', function()
    local dir, project, bib

    before_each(function()
      dir = H.tmpdir()
      project = H.project(dir .. '/main.tex')
      bib = dir .. '/refs.bib'
      H.write(project.main, { '\\addbibresource{refs.bib}' })
      H.write(bib, { '@misc{old,', '  title = {Old},', '}' })
      fake_dblp()
      vim.ui.select = function(items, opts, on_choice)
        T.matches('Leißa, Köster · A graph%-based', opts.format_item(items[1]))
        on_choice(items[1])
      end
    end)

    it('appends the entry and cites it under the edited key', function()
      local prompts = {}
      vim.ui.input = function(opts, on_confirm)
        prompts[#prompts + 1] = opts.default
        on_confirm('leissa:thorin')
      end
      H.buf({ 'See \\cite{old}.' })
      H.cursor_at('}.')
      cite.cite(project, 'leißa graph')

      T.eq({ 'leissa2015graph' }, prompts)
      T.eq({ 'See \\cite{old,leissa:thorin}.' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      local lines = vim.fn.readfile(bib)
      T.eq('', lines[4])
      T.eq('@inproceedings{leissa:thorin,', lines[5])
      T.contains(lines, '  author    = {Roland Leißa and Marcel Köster and Sebastian Hack},')
      T.eq('}', lines[#lines])
    end)

    it('asks for the query and takes the suggested key when told not to ask', function()
      config.setup({ cite = { edit_key = false } })
      vim.ui.input = function(opts, on_confirm)
        T.eq('Search: ', opts.prompt)
        on_confirm('leißa graph')
      end
      H.buf({ '' })
      cite.cite(project)
      T.eq({ '\\cite{leissa2015graph}' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it('cites an entry that is already in the bibliography without adding it again', function()
      H.write(bib, { '@inproceedings{mine,', '  doi = {10.1109/CGO.2015.7054200},', '}' })
      vim.ui.input = function()
        error('no key prompt expected')
      end
      H.buf({ 'x' })
      cite.cite(project, 'leißa graph')
      T.eq({ 'x\\cite{mine}' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      T.eq(3, #vim.fn.readfile(bib))
      T.ok(H.notified('already in refs.bib as mine'))
    end)

    it('appends to a loaded bib buffer and writes it', function()
      config.setup({ cite = { edit_key = false } })
      H.buf({ '' })
      local bibbuf = vim.fn.bufadd(bib)
      vim.fn.bufload(bibbuf)
      cite.cite(project, 'leißa graph')
      T.eq('@inproceedings{leissa2015graph,', vim.api.nvim_buf_get_lines(bibbuf, 4, 5, false)[1])
      T.falsy(vim.bo[bibbuf].modified)
      T.eq('@inproceedings{leissa2015graph,', vim.fn.readfile(bib)[5])
      vim.api.nvim_buf_delete(bibbuf, { force = true })
    end)

    it('leaves a bib buffer with unsaved changes unsaved', function()
      config.setup({ cite = { edit_key = false } })
      H.buf({ '' })
      local bibbuf = vim.fn.bufadd(bib)
      vim.fn.bufload(bibbuf)
      vim.api.nvim_buf_set_lines(bibbuf, 0, 0, false, { '% draft' })
      cite.cite(project, 'leißa graph')
      T.eq('@inproceedings{leissa2015graph,', vim.api.nvim_buf_get_lines(bibbuf, 5, 6, false)[1])
      T.ok(vim.bo[bibbuf].modified)
      T.eq(3, #vim.fn.readfile(bib))
      T.ok(H.notified('%(unsaved%)'))
      vim.api.nvim_buf_delete(bibbuf, { force = true })
    end)

    it('reports a missing bibliography', function()
      H.write(project.main, { '\\documentclass{article}' })
      vim.fn.delete(bib)
      H.buf({ '' })
      cite.cite(project, 'x')
      T.ok(H.notified('no bibliography'))
    end)

    it('reports a failed search', function()
      dblp.post = function(_, done)
        done('curl: (28) timed out')
      end
      H.buf({ '' })
      cite.cite(project, 'x')
      T.ok(H.notified('DBLP search failed: curl: %(28%) timed out'))
    end)
  end)
end)
