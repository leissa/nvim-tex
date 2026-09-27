--- DBLP as a `:TexCite` source.
---
--- DBLP's search API and its `.bib` export sit behind a JavaScript bot check
--- that `curl` cannot pass, so both the search and the BibTeX entry go
--- through the SPARQL endpoint instead, which is meant for programs. The
--- entry is assembled from the RDF and follows DBLP's own export closely.
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = {}

M.name = 'DBLP'

local PREFIXES = table.concat({
  'PREFIX dblp: <https://dblp.org/rdf/schema#>',
  'PREFIX ql: <http://qlever.cs.uni-freiburg.de/builtin-functions/>',
  '',
}, '\n')

local REC = 'https://dblp.org/rec/'

---@return table
local function options()
  return config.get('cite', 'dblp') or {}
end

--- POST a SPARQL query and hand the decoded JSON result to `done`. Replaced
--- by the tests.
---@param query string
---@param done fun(err: string|nil, result: table|nil)
function M.post(query, done)
  local cite = config.get('cite')
  local cmd = util.as_cmd(cite.curl)
  if not util.executable(cmd[1]) then
    done(("'%s' is not executable"):format(cmd[1]))
    return
  end
  vim.list_extend(cmd, {
    '--silent',
    '--show-error',
    '--fail',
    '--max-time',
    tostring(cite.timeout),
    '--header',
    'Accept: application/sparql-results+json',
    '--data-urlencode',
    'query=' .. query,
    options().endpoint,
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        done(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or ('curl exited with ' .. result.code))
        return
      end
      local ok, decoded = pcall(vim.json.decode, result.stdout or '')
      if not ok or type(decoded) ~= 'table' or not decoded.results then
        done('unexpected answer from ' .. options().endpoint)
        return
      end
      done(nil, decoded)
    end)
  end)
end

--- The rows of a SPARQL JSON result as `{ var = value }` tables.
---@param result table
---@return table[]
local function rows(result)
  local out = {}
  for _, binding in ipairs(result.results.bindings or {}) do
    local row = {}
    for var, cell in pairs(binding) do
      row[var] = cell.value
    end
    out[#out + 1] = row
  end
  return out
end

--- The search words of `query`: lower case, split at spaces and ASCII
--- punctuation, which also drops everything that could break out of a
--- SPARQL string.
---@param query string
---@return string[]
function M.words(query)
  local out = {}
  for word in vim.fn.tolower(query):gmatch('[^%s%p]+') do
    out[#out + 1] = word
  end
  return out
end

--- `query` normalised the way the search query normalises titles, to rank
--- titles that contain it as a phrase first.
---@param query string
---@return string
function M.phrase(query)
  return vim.trim((query:lower():gsub('[^a-z0-9]+', ' ')))
end

--- Every word has to occur in the title or in an author's name. The last one
--- is a prefix, as it may not be typed out yet. Titles that contain the query
--- as a phrase come first, the shortest of them -- the exact title -- on top;
--- the rest newest first.
---@param query string
---@param limit integer
---@return string|nil
function M.search_query(query, limit)
  local words = M.words(query)
  if #words == 0 then
    return nil
  end
  local blocks = {}
  for i, word in ipairs(words) do
    if i == #words and #word >= 3 then
      word = word .. '*'
    end
    local match = ('?t%d ql:contains-word "%s" . ?t%d ql:contains-entity ?e%d .'):format(i, word, i, i)
    blocks[#blocks + 1] = ('  { %s ?pub dblp:title ?e%d } UNION { %s ?pub dblp:authoredBy/dblp:primaryCreatorName ?e%d }'):format(
      match,
      i,
      match,
      i
    )
  end
  return PREFIXES
    .. 'SELECT DISTINCT ?pub ?title ?year WHERE {\n'
    .. table.concat(blocks, '\n')
    .. '\n  ?pub dblp:title ?title .\n'
    .. '  OPTIONAL { ?pub dblp:yearOfPublication ?year }\n'
    .. ('  BIND(CONTAINS(REPLACE(LCASE(?title), "[^a-z0-9]+", " "), "%s") AS ?phrase)\n'):format(M.phrase(query))
    .. ('} ORDER BY DESC(?phrase) ASC(IF(?phrase, STRLEN(?title), 0)) DESC(?year) LIMIT %d\n'):format(limit)
end

--- Venue, type and authors of the publications found by the search, one
--- row each: the authors as `?ord`/`?name`, the rest with `?type`/`?venue`.
--- The signatures must not be `OPTIONAL`: QLever then scans all of them.
---@param pubs string[]
---@return string
function M.summary_query(pubs)
  local values = ('VALUES ?pub { %s }'):format(table.concat(
    vim.tbl_map(function(pub)
      return '<' .. pub .. '>'
    end, pubs),
    ' '
  ))
  return PREFIXES
    .. 'SELECT ?pub ?type ?venue ?ord ?name WHERE {\n'
    .. ('  { %s ?pub dblp:bibtexType ?type . OPTIONAL { ?pub dblp:publishedIn ?venue } }\n'):format(values)
    .. ('  UNION { %s ?pub dblp:hasSignature ?sig . ?sig dblp:signatureOrdinal ?ord ; dblp:signatureDblpName ?name }\n'):format(
      values
    )
    .. '}\n'
end

--- Everything needed for the BibTeX entry of `pub`: its own triples, its
--- author and editor signatures, and the triples of the proceedings or book
--- it is part of.
---@param pub string
---@return string
function M.entry_query(pub)
  local iri = '<' .. pub .. '>'
  local function signatures(kind, class)
    return ('  UNION { VALUES ?k { "%s" } %s dblp:hasSignature ?s . ?s a dblp:%s ; dblp:signatureOrdinal ?p ; dblp:signatureDblpName ?o }\n'):format(
      kind,
      iri,
      class
    )
  end
  return PREFIXES
    .. 'SELECT ?k ?p ?o WHERE {\n'
    .. ('  { VALUES ?k { "pub" } %s ?p ?o }\n'):format(iri)
    .. signatures('author', 'AuthorSignature')
    .. signatures('editor', 'EditorSignature')
    .. ('  UNION { VALUES ?k { "book" } %s dblp:publishedAsPartOf ?b . ?b ?p ?o }\n'):format(iri)
    .. '}\n'
end

--- DBLP disambiguates homonyms with a number: `Wei Wang 0001`.
---@param name string
---@return string
function M.clean_name(name)
  return (name:gsub('%s+%d%d%d%d$', ''))
end

--- `1:Roland Leißa|2:Marcel Köster` in ordinal order, without the ordinals.
---@param concat string|nil
---@return string[]
function M.ordered_names(concat)
  local named = {}
  for part in (concat or ''):gmatch('[^|]+') do
    local ord, name = part:match('^(%d+):(.*)$')
    if ord then
      named[#named + 1] = { tonumber(ord), M.clean_name(name) }
    end
  end
  table.sort(named, function(a, b)
    return a[1] < b[1]
  end)
  return vim.tbl_map(function(pair)
    return pair[2]
  end, named)
end

---@param iri string|nil `http://purl.org/net/nknouf/ns/bibtex#Inproceedings`
---@return string
local function bibtex_type(iri)
  return ((iri or ''):match('#(%w+)$') or 'misc'):lower()
end

---@param title string
---@return string
local function strip_period(title)
  return (title:gsub('%.$', ''))
end

--- Search DBLP.
---@param query string
---@param done fun(err: string|nil, items: table[]|nil)
function M.search(query, done)
  local sparql = M.search_query(query, options().max_results or 30)
  if not sparql then
    done(nil, {})
    return
  end
  M.post(sparql, function(err, result)
    if err then
      done(err)
      return
    end
    local found = rows(result)
    if #found == 0 then
      done(nil, {})
      return
    end
    local pubs = vim.tbl_map(function(row)
      return row.pub
    end, found)
    M.post(M.summary_query(pubs), function(err2, result2)
      if err2 then
        done(err2)
        return
      end
      local summary = vim.defaulttable(function()
        return { names = {} }
      end)
      for _, row in ipairs(rows(result2)) do
        local entry = summary[row.pub]
        if row.name then
          entry.names[#entry.names + 1] = row.ord .. ':' .. row.name
        else
          entry.type, entry.venue = row.type, row.venue
        end
      end
      local items = {}
      for _, row in ipairs(found) do
        local extra = summary[row.pub]
        items[#items + 1] = {
          source = M,
          id = row.pub,
          title = strip_period(row.title),
          year = row.year,
          venue = extra.venue,
          type = bibtex_type(extra.type),
          authors = M.ordered_names(table.concat(extra.names, '|')),
        }
      end
      done(nil, items)
    end)
  end)
end

--- Group the rows of the entry query: `{ pub = { [prop] = { values } },
--- book = ..., author = { names }, editor = { names } }`, with the property
--- IRIs shortened to their local names.
---@param found table[]
---@return table
function M.group(found)
  local data = { pub = {}, book = {}, author = {}, editor = {} }
  local sigs = { author = {}, editor = {} }
  for _, row in ipairs(found) do
    if row.k == 'author' or row.k == 'editor' then
      sigs[row.k][#sigs[row.k] + 1] = row.p .. ':' .. row.o
    elseif data[row.k] then
      local prop = row.p:match('[#/]([%w_]+)$') or row.p
      local values = data[row.k][prop] or {}
      if not vim.tbl_contains(values, row.o) then
        values[#values + 1] = row.o
      end
      data[row.k][prop] = values
    end
  end
  data.author = M.ordered_names(table.concat(sigs.author, '|'))
  data.editor = M.ordered_names(table.concat(sigs.editor, '|'))
  return data
end

--- `202-212` -> `202--212`.
---@param pages string
---@return string
local function page_range(pages)
  return (pages:gsub('%f[%-]%-%f[^%-]', '--'))
end

--- The BibTeX entry for grouped entry data. `id` is the record IRI.
---@param id string
---@param data table as returned by `M.group`
---@return table `{ type, fields, authors, editors, year, title, dblp }`
function M.build(id, data)
  local pub, book = data.pub, data.book
  local function first(tbl, prop)
    return tbl[prop] and tbl[prop][1] or nil
  end

  local type = bibtex_type(first(pub, 'bibtexType'))
  local fields = {}
  local function add(name, value)
    if value and value ~= '' then
      fields[#fields + 1] = { name, value }
    end
  end

  add('author', table.concat(data.author, ' and '))
  if type == 'proceedings' or type == 'book' then
    add('editor', table.concat(data.editor, ' and '))
  end
  local title = strip_period(first(pub, 'title') or '')
  add('title', title)

  if type == 'article' then
    add('journal', first(pub, 'publishedInJournal') or first(pub, 'publishedIn'))
    add('volume', first(pub, 'publishedInJournalVolume'))
    add('number', first(pub, 'publishedInJournalVolumeIssue'))
  elseif type == 'inproceedings' or type == 'incollection' then
    add('booktitle', book.title and strip_period(book.title[1]) or first(pub, 'publishedInBook'))
    add('series', first(book, 'publishedInSeries'))
    add('volume', first(book, 'publishedInSeriesVolume'))
  elseif type == 'proceedings' or type == 'book' then
    add('series', first(pub, 'publishedInSeries'))
    add('volume', first(pub, 'publishedInSeriesVolume'))
  end
  local pages = first(pub, 'pagination')
  add('pages', pages and page_range(pages))
  add('publisher', first(pub, 'publishedBy') or first(book, 'publishedBy'))
  add('school', first(pub, 'thesisAcceptedBySchool'))
  local year = first(pub, 'yearOfPublication')
  add('year', year)
  local isbn = first(pub, 'isbn')
  add('isbn', isbn and isbn:gsub('^urn:isbn:', '') or nil)
  add('url', first(pub, 'primaryDocumentPage'))
  local doi = first(pub, 'doi')
  add('doi', doi and doi:gsub('^https?://[^/]*doi%.org/', '') or nil)
  for _, page in ipairs(pub.documentPage or {}) do
    local arxiv = page:match('^https?://arxiv%.org/abs/(.+)$')
    if arxiv then
      add('eprinttype', 'arXiv')
      add('eprint', arxiv)
      break
    end
  end

  local dblp = id:sub(#REC + 1)
  add('biburl', REC .. dblp .. '.bib')
  add('bibsource', 'dblp computer science bibliography, https://dblp.org')

  return {
    type = type,
    fields = fields,
    authors = data.author,
    editors = data.editor,
    year = year,
    title = title,
    doi = doi and doi:gsub('^https?://[^/]*doi%.org/', '') or nil,
    biburl = REC .. dblp .. '.bib',
    source_key = 'DBLP:' .. dblp,
  }
end

--- Fetch the BibTeX entry of a search result.
---@param item table
---@param done fun(err: string|nil, entry: table|nil)
function M.entry(item, done)
  if not vim.startswith(item.id, REC) or item.id:find('[^%w%-_/%.:]') then
    done('not a DBLP record: ' .. item.id)
    return
  end
  M.post(M.entry_query(item.id), function(err, result)
    if err then
      done(err)
      return
    end
    local found = rows(result)
    if #found == 0 then
      done('DBLP has no record ' .. item.id)
      return
    end
    done(nil, M.build(item.id, M.group(found)))
  end)
end

return M
