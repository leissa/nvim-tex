--- Show a compiled fragment in a floating window at the cursor, with
--- snacks.nvim's image support, until the cursor moves. Not a `view.method`
--- backend: it has no forward or inverse search, and suits cropped fragments
--- rather than whole documents.
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')
local util = require('nvim-tex.util')

local M = {}

--- snacks.nvim's image module, when `view.snacks` is on, snacks' image
--- support is enabled and the terminal can show images.
---@return table|nil
local function snacks_image()
  if not config.get('view', 'snacks') then
    return nil
  end
  local ok, snacks = pcall(require, 'snacks')
  local image = ok and snacks.image or nil
  if not image or image.config.enabled ~= true or not image.supports_terminal() then
    return nil
  end
  return image
end

---@return boolean
function M.available()
  return snacks_image() ~= nil
end

--- The floating window showing the last fragment.
---@type { buf: integer, win: integer|nil, placement: table, pdf: string }|nil
local float

local augroup = vim.api.nvim_create_augroup('nvim-tex.viewer.float', { clear = true })

--- Close the floating window, and remove the files made for it.
function M.close()
  vim.api.nvim_clear_autocmds({ group = augroup })
  if not float then
    return
  end
  local f = float
  float = nil
  f.placement:close()
  if f.win and vim.api.nvim_win_is_valid(f.win) then
    vim.api.nvim_win_close(f.win, true)
  end
  if vim.api.nvim_buf_is_valid(f.buf) then
    vim.api.nvim_buf_delete(f.buf, { force = true })
  end
  vim.fn.delete(f.pdf)
  -- The image snacks converted the copy to, in its cache.
  if f.placement.img and f.placement.img.file ~= f.pdf then
    vim.fn.delete(f.placement.img.file)
  end
end

vim.api.nvim_create_autocmd('VimLeavePre', { callback = M.close })

--- Show the PDF of `project` in a floating window at the cursor.
---@param project table
---@return boolean shown
function M.show(project)
  local image = snacks_image()
  if not image then
    return false
  end
  M.close()
  -- snacks caches the converted image by the path of the PDF: give every
  -- compilation its own.
  local pdf = project_mod.output_file(project)
  local stat = vim.uv.fs_stat(pdf)
  if not stat then
    return false
  end
  local copy = util.join(project.out_dir, ('%s-%d%09d.pdf'):format(project.name, stat.mtime.sec, stat.mtime.nsec))
  if not vim.uv.fs_copyfile(pdf, copy) then
    util.error('could not copy ' .. pdf)
    return false
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local f = { buf = buf, pdf = copy }
  f.placement = image.placement.new(
    buf,
    copy,
    vim.tbl_extend('force', {}, image.config.doc or {}, {
      inline = false,
      -- Open the window once the image is converted and its size known.
      on_update_pre = function(placement)
        if f.win or float ~= f then
          return
        end
        local loc = placement:state().loc
        f.win = vim.api.nvim_open_win(buf, false, {
          relative = 'cursor',
          row = 1,
          col = 0,
          width = loc.width,
          height = loc.height,
          style = 'minimal',
          focusable = false,
        })
        vim.wo[f.win].wrap = false
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufLeave', 'WinLeave' }, {
          group = augroup,
          once = true,
          callback = function()
            vim.schedule(M.close)
          end,
        })
      end,
    })
  )
  float = f
  return true
end

return M
