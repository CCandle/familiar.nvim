local M = {}

local state = {
  ns = vim.api.nvim_create_namespace("familiar_pixels"),
  buf = nil,
  win = nil,
  parent = nil,
  width = nil,
  height = nil,
  highlights = {},
  last_draw = nil,
}

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function ensure_buffer()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].modifiable = true
  return state.buf
end

local function define_base_highlight()
  -- The render surface is a floating window. Make its untouched cells fully
  -- transparent; pixel foregrounds remain visible, and mixed top/bottom cells
  -- explicitly override blending in color_group().
  vim.api.nvim_set_hl(0, "FamiliarTransparent", { blend = 100 })
end

local function color_group(top, bottom, palette)
  local key = (top or "_") .. "_" .. (bottom or "_")
  if state.highlights[key] then
    return state.highlights[key]
  end

  local safe = key:gsub("[^%w_]", "_")
  local group = "FamiliarPixel_" .. safe
  local spec = {}
  if top then
    spec.fg = palette[top]
  elseif bottom then
    spec.fg = palette[bottom]
  end

  -- A different lower pixel needs an actual cell background. Keep that pair
  -- opaque even though the surrounding render surface uses winblend=100.
  if top and bottom and top ~= bottom then
    spec.bg = palette[bottom]
    spec.blend = 0
  end

  vim.api.nvim_set_hl(0, group, spec)
  state.highlights[key] = group
  return group
end

local function cell(top, bottom, palette)
  if not top and not bottom then
    return " ", nil
  end
  if top and bottom and top == bottom then
    return "█", color_group(top, nil, palette)
  end
  if top and bottom then
    return "▀", color_group(top, bottom, palette)
  end
  if top then
    return "▀", color_group(top, nil, palette)
  end
  return "▄", color_group(nil, bottom, palette)
end

local function frame_lines(avatar, frame)
  local lines = {}
  local spans = {}
  local transparent = "."

  for y = 1, avatar.height, 2 do
    local top_row = frame[y]
    local bottom_row = frame[y + 1]
    local parts = {}
    local row_spans = {}
    local byte_col = 0

    for x = 1, avatar.width do
      local top = top_row:sub(x, x)
      local bottom = bottom_row:sub(x, x)
      if top == transparent then top = nil end
      if bottom == transparent then bottom = nil end

      local glyph, hl = cell(top, bottom, avatar.palette)
      parts[#parts + 1] = glyph
      local bytes = #glyph
      local next_col = byte_col + bytes

      -- Transparent spaces inherit FamiliarTransparent, so they need no
      -- extmark. Merge adjacent equal-color cells to keep per-frame extmark
      -- churn small even when the sprite grows beyond the current 16x16 fox.
      if hl then
        local previous = row_spans[#row_spans]
        if previous and previous[3] == hl and previous[2] == byte_col then
          previous[2] = next_col
        else
          row_spans[#row_spans + 1] = { byte_col, next_col, hl }
        end
      end

      byte_col = next_col
    end

    lines[#lines + 1] = table.concat(parts)
    spans[#spans + 1] = row_spans
  end

  return lines, spans
end

local function ensure_window(parent, width, height, row, col)
  local buf = ensure_buffer()
  if valid_win(state.win) and state.parent == parent and state.width == width and state.height == height then
    vim.api.nvim_win_set_config(state.win, {
      relative = "win",
      win = parent,
      anchor = "NW",
      row = row,
      col = col,
      width = width,
      height = height,
    })
    return state.win
  end

  if valid_win(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end

  state.win = vim.api.nvim_open_win(buf, false, {
    relative = "win",
    win = parent,
    anchor = "NW",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    focusable = false,
    mouse = false,
    zindex = 45,
  })
  state.parent = parent
  state.width = width
  state.height = height

  vim.wo[state.win].wrap = false
  vim.wo[state.win].winblend = 100
  vim.wo[state.win].winhighlight = "Normal:FamiliarTransparent,NormalFloat:FamiliarTransparent,EndOfBuffer:FamiliarTransparent"
  return state.win
end

local function last_char_byte_col(line)
  local chars = vim.fn.strchars(line)
  if chars <= 0 then
    return 1
  end
  return vim.fn.byteidx(line, chars - 1) + 1
end

local function right_edges(win)
  local height = vim.api.nvim_win_get_height(win)
  local width = vim.api.nvim_win_get_width(win)
  local pos = vim.api.nvim_win_get_position(win)
  local edges = {}
  for row = 0, height - 1 do
    edges[row] = -1
  end

  local bounds = vim.api.nvim_win_call(win, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end)
  local top, bottom = bounds[1], bounds[2]

  for lnum = top, bottom do
    local line = (vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), lnum - 1, lnum, false)[1] or "")
    local first = vim.fn.screenpos(win, lnum, 1)
    if first.row and first.row > 0 then
      local r1 = first.row - pos[1] - 1
      local last = vim.fn.screenpos(win, lnum, last_char_byte_col(line))

      if last.row and last.row > 0 then
        local r2 = last.row - pos[1] - 1
        if r1 == r2 then
          local edge = (last.endcol or last.col) - pos[2] - 1
          if r1 >= 0 and r1 < height then
            edges[r1] = math.max(edges[r1], edge)
          end
        else
          for row = math.max(0, r1), math.min(height - 1, r2 - 1) do
            edges[row] = width - 1
          end
          if r2 >= 0 and r2 < height then
            edges[r2] = math.max(edges[r2], (last.endcol or last.col) - pos[2] - 1)
          end
        end
      elseif r1 >= 0 and r1 < height then
        for row = r1, height - 1 do
          edges[row] = width - 1
        end
      end
    end
  end

  return edges
end

function M.find_safe_position(win, avatar, opts)
  if not valid_win(win) then return nil end
  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  local sprite_w = avatar.width
  local sprite_h = avatar.height / 2
  local margin = opts.margin or 1

  if width < (opts.min_width or 1) or height < (opts.min_height or 1) then
    return nil
  end
  if sprite_w + margin * 2 >= width or sprite_h + margin * 2 >= height then
    return nil
  end

  local x = width - sprite_w - margin
  local edges = right_edges(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local cursor_screen = vim.fn.screenpos(win, cursor[1], cursor[2] + 1)
  local win_pos = vim.api.nvim_win_get_position(win)
  local desired = height - sprite_h - margin
  if cursor_screen.row and cursor_screen.row > 0 then
    desired = math.min(desired, math.max(margin, cursor_screen.row - win_pos[1] + 1))
  end

  local best, best_score
  for row = margin, height - sprite_h - margin do
    local safe = true
    for r = row, row + sprite_h - 1 do
      if (edges[r] or -1) >= x - margin then
        safe = false
        break
      end
    end
    if safe then
      local score = math.abs(row - desired)
      if not best_score or score < best_score then
        best = { x = x, y = row }
        best_score = score
      end
    end
  end

  return best
end

function M.draw(parent, avatar, frame_name, position)
  if not position or not valid_win(parent) then
    M.hide()
    return
  end
  local frame = avatar.frames[frame_name]
  if not frame then return end

  local draw_key = table.concat({ avatar.id, parent, frame_name, position.x, position.y }, ":")
  if state.last_draw == draw_key and valid_win(state.win) then
    return
  end

  define_base_highlight()
  local lines, spans = frame_lines(avatar, frame)
  local win = ensure_window(parent, avatar.width, avatar.height / 2, position.y, position.x)
  local buf = ensure_buffer()

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)
  for row, row_spans in ipairs(spans) do
    for _, span in ipairs(row_spans) do
      vim.api.nvim_buf_set_extmark(buf, state.ns, row - 1, span[1], {
        end_col = span[2],
        hl_group = span[3],
        priority = 200,
      })
    end
  end
  vim.bo[buf].modifiable = false

  if valid_win(win) then
    vim.api.nvim_win_set_config(win, {
      relative = "win",
      win = parent,
      anchor = "NW",
      row = position.y,
      col = position.x,
      width = avatar.width,
      height = avatar.height / 2,
    })
    state.last_draw = draw_key
  end
end

function M.hide()
  if valid_win(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
  state.parent = nil
  state.last_draw = nil
end

function M.stop()
  M.hide()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.buf = nil
  state.highlights = {}
  state.last_draw = nil
end

function M._frame_lines(avatar, frame_name)
  return frame_lines(avatar, assert(avatar.frames[frame_name]))
end

return M
