local H = require('tests.helpers')
local nodes = require('nvim-tex.tikz.nodes')
local tikz = require('nvim-tex.tikz')
local ts = require('nvim-tex.ts')

local PIC = {
  '\\begin{tikzpicture}[a/.style={draw}, thick line/.style={}]', -- 1
  '  \\node[draw] (a) at (0,0) {A};', -- 2
  '  \\node at (1,0) (b) {B}; % (a) in a comment', -- 3
  '  \\node (my node) [right=of a] {C};', -- 4
  '  \\draw (a.north) -- ($(a)!0.5!(b)$) node[name=mid] {} circle (2pt);', -- 5
  '  \\coordinate (c) at (2,2);', -- 6
  '  \\draw (mid) -- (my node);', -- 7
  '\\end{tikzpicture}', -- 8
}

---@param bufnr integer
---@return TSNode
local function picture(bufnr)
  return tikz.picture(ts.node_at_cursor(bufnr, { 2, 2 }), bufnr)
end

--- `row:col` (1-indexed row) of each occurrence of `name`.
---@param bufnr integer
---@param name string
---@return string[]
local function places(bufnr, name)
  return vim.tbl_map(function(occurrence)
    return (occurrence.range[1] + 1) .. ':' .. occurrence.range[2]
  end, nodes.occurrences(picture(bufnr), bufnr, name))
end

describe('tikz nodes', function()
  before_each(H.need_parser)
  after_each(H.cleanup)

  it('finds the names a picture defines, wherever the name sits', function()
    local bufnr = H.buf(PIC)
    T.eq(
      { 'a', 'b', 'my node', 'mid', 'c' },
      vim.tbl_map(function(definition)
        return definition.name
      end, nodes.definitions(picture(bufnr), bufnr))
    )
  end)

  it('finds a name as a coordinate, with an anchor, in calc and after of', function()
    local bufnr = H.buf(PIC)
    T.eq({ '2:15', '4:28', '5:9', '5:24' }, places(bufnr, 'a'))
    T.eq({ '4:9', '7:18' }, places(bufnr, 'my node'))
    T.eq({ '5:47', '7:9' }, places(bufnr, 'mid'))
  end)

  it('ignores comments and coordinates that only look like a name', function()
    local bufnr = H.buf(PIC)
    T.eq({ '3:18', '5:32' }, places(bufnr, 'b'))
    -- `circle (2pt)`: no node is called `2pt`.
    T.eq(nil, (nodes.name_at(bufnr, 4, 64)))
  end)

  it('jumps to the definition of the node under the cursor', function()
    H.buf(PIC)
    H.cursor(7, 20)
    T.ok(nodes.goto_definition())
    T.eq({ 4, 9 }, vim.api.nvim_win_get_cursor(0))
    H.cursor(6, 3)
    T.eq(false, nodes.goto_definition())
  end)

  it('renames a node throughout its picture', function()
    local bufnr = H.buf(PIC)
    H.cursor(5, 9)
    nodes.rename('x')
    local lines = H.lines(bufnr)
    T.eq('  \\node[draw] (x) at (0,0) {A};', lines[2])
    T.eq('  \\node at (1,0) (b) {B}; % (a) in a comment', lines[3])
    T.eq('  \\node (my node) [right=of x] {C};', lines[4])
    T.eq('  \\draw (x.north) -- ($(x)!0.5!(b)$) node[name=mid] {} circle (2pt);', lines[5])
    T.ok(H.notified('renamed a to x in 4 places'))
  end)

  it('completes node and style names', function()
    H.buf(PIC)
    H.cursor(7, 11)
    local words = vim.tbl_map(function(item)
      return item.word .. ':' .. item.kind
    end, nodes.complete(0, 'm'))
    T.eq({ 'my node:node', 'mid:node' }, words)
    T.eq(
      { 'thick line:style' },
      vim.tbl_map(function(item)
        return item.word .. ':' .. item.kind
      end, nodes.complete(0, 't'))
    )
    T.eq(
      { 'a:node' },
      vim.tbl_map(function(item)
        return item.word .. ':' .. item.kind
      end, nodes.complete(0, 'a'))
    )
  end)
end)
