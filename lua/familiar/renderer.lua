local M = {}

local state = {
  ns = vim.api.nvim_create_namespace("familiar_render"),
  buf = nil,
  win = nil,
  parent = nil,
  width = nil,
  height = nil,
  highlights = {},
  last_content_key = nil,
  last_position_key = nil,
  safety_context = nil,
  safety_opts = nil,
  trail = {
    pool = {},
    highlights = {},
  },
  stats = {
    content_updates = 0,
    position_updates = 0,
    position_skips = 0,
    trail_updates = 0,
    safety_suppressed = 0,
  },
}

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function avatar_kind(avatar)
  return avatar.kind or "pixel"
end

local function render_height(avatar)
  if avatar_kind(avatar) == "pixel" then
    return avatar.height / 2
  end
  return avatar.height
end

local function round(v)
  return math.floor(v + 0.5)
end

local function quantize_position(position)
  return { x = round(position.x), y = round(position.y) }
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
  vim.api.nvim_set_hl(0, "FamiliarTransparent", { blend = 100 })
end

local function pixel_color_group(top, bottom, palette)
  local key = "pixel:" .. (top or "_") .. "_" .. (bottom or "_")
  if state.highlights[key] then return state.highlights[key] end

  local safe = key:gsub("[^%w_]", "_")
  local group = "FamiliarPixel_" .. safe
  local spec = {}
  if top then
    spec.fg = palette[top]
  elseif bottom then
    spec.fg = palette[bottom]
  end
  if top and bottom and top ~= bottom then
    spec.bg = palette[bottom]
    spec.blend = 0
  end
  vim.api.nvim_set_hl(0, group, spec)
  state.highlights[key] = group
  return group
end

local function glyph_color_group(avatar, role)
  local color = avatar.palette[role]
  local key = table.concat({ "glyph", avatar.id, role, color }, ":")
  if state.highlights[key] then return state.highlights[key] end

  local safe = (avatar.id .. "_" .. role):gsub("[^%w_]", "_")
  local group = "FamiliarGlyph_" .. safe
  vim.api.nvim_set_hl(0, group, { fg = color })
  state.highlights[key] = group
  return group
end

local function pixel_cell(top, bottom, palette)
  if not top and not bottom then return " ", nil end
  if top and bottom and top == bottom then return "█", pixel_color_group(top, nil, palette) end
  if top and bottom then return "▀", pixel_color_group(top, bottom, palette) end
  if top then return "▀", pixel_color_group(top, nil, palette) end
  return "▄", pixel_color_group(nil, bottom, palette)
end

local function pixel_frame_lines(avatar, frame)
  local lines, spans = {}, {}
  local transparent = "."

  for y = 1, avatar.height, 2 do
    local top_row, bottom_row = frame[y], frame[y + 1]
    local parts, row_spans = {}, {}
    local byte_col = 0

    for x = 1, avatar.width do
      local top, bottom = top_row:sub(x, x), bottom_row:sub(x, x)
      if top == transparent then top = nil end
      if bottom == transparent then bottom = nil end
      local glyph, hl = pixel_cell(top, bottom, avatar.palette)
      parts[#parts + 1] = glyph
      local next_col = byte_col + #glyph
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

local function glyph_frame_lines(avatar, frame)
  local lines, spans = {}, {}
  local top_padding = avatar.height - #frame.rows

  for _ = 1, top_padding do
    lines[#lines + 1] = string.rep(" ", avatar.width)
    spans[#spans + 1] = {}
  end

  for _, row in ipairs(frame.rows) do
    local parts, row_spans = {}, {}
    local byte_col = 0

    for _, segment in ipairs(row) do
      local text = segment.text
      parts[#parts + 1] = text
      local next_col = byte_col + #text
      if segment.role then
        local hl = glyph_color_group(avatar, segment.role)
        local previous = row_spans[#row_spans]
        if previous and previous[3] == hl and previous[2] == byte_col then
          previous[2] = next_col
        else
          row_spans[#row_spans + 1] = { byte_col, next_col, hl }
        end
      end
      byte_col = next_col
    end

    local line = table.concat(parts)
    local padding = avatar.width - vim.fn.strdisplaywidth(line)
    if padding > 0 then line = line .. string.rep(" ", padding) end
    lines[#lines + 1] = line
    spans[#spans + 1] = row_spans
  end

  return lines, spans
end

local function frame_lines(avatar, frame)
  if avatar_kind(avatar) == "glyph" then return glyph_frame_lines(avatar, frame) end
  return pixel_frame_lines(avatar, frame)
end

local function close_surface()
  if valid_win(state.win) then pcall(vim.api.nvim_win_close, state.win, true) end
  state.win = nil
  state.parent = nil
  state.width = nil
  state.height = nil
  state.last_position_key = nil
end

local function ensure_window(parent, width, height, position)
  local q = quantize_position(position)
  local buf = ensure_buffer()

  if valid_win(state.win) and state.parent == parent and state.width == width and state.height == height then
    return state.win, q, false
  end

  close_surface()
  state.win = vim.api.nvim_open_win(buf, false, {
    relative = "win",
    win = parent,
    anchor = "NW",
    row = q.y,
    col = q.x,
    width = width,
    height = height,
    style = "minimal",
    focusable = false,
    mouse = false,
    noautocmd = true,
    zindex = 45,
  })
  state.parent, state.width, state.height = parent, width, height
  vim.wo[state.win].wrap = false
  vim.wo[state.win].winblend = 100
  vim.wo[state.win].winhighlight =
    "Normal:FamiliarTransparent,NormalFloat:FamiliarTransparent,EndOfBuffer:FamiliarTransparent"
  state.last_position_key = table.concat({ parent, q.x, q.y, width, height }, ":")
  return state.win, q, true
end

local function position_surface(parent, avatar, position)
  local height = render_height(avatar)
  local win, q, created = ensure_window(parent, avatar.width, height, position)
  if created then
    state.stats.position_updates = state.stats.position_updates + 1
    return win, q, true
  end

  local key = table.concat({ parent, q.x, q.y, avatar.width, height }, ":")
  if key == state.last_position_key then
    state.stats.position_skips = state.stats.position_skips + 1
    return win, q, false
  end

  vim.api.nvim_win_set_config(win, {
    relative = "win",
    win = parent,
    anchor = "NW",
    row = q.y,
    col = q.x,
    width = avatar.width,
    height = height,
  })
  state.last_position_key = key
  state.stats.position_updates = state.stats.position_updates + 1
  return win, q, true
end

local function last_char_byte_col(line)
  local chars = vim.fn.strchars(line)
  if chars <= 0 then return 1 end
  return vim.fn.byteidx(line, chars - 1) + 1
end

local function virtual_text_width(chunks)
  local width = 0
  for _, chunk in ipairs(chunks or {}) do width = width + vim.fn.strdisplaywidth(chunk[1] or "") end
  return width
end

local function right_edges(win)
  local height = vim.api.nvim_win_get_height(win)
  local width = vim.api.nvim_win_get_width(win)
  local pos = vim.api.nvim_win_get_position(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local edges = {}
  for row = 0, height - 1 do edges[row] = -1 end

  local bounds = vim.api.nvim_win_call(win, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end)
  local top, bottom = bounds[1], bounds[2]

  for lnum = top, bottom do
    local line = (vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or "")
    local first = vim.fn.screenpos(win, lnum, 1)
    if first.row and first.row > 0 then
      local r1 = first.row - pos[1] - 1
      local last = vim.fn.screenpos(win, lnum, last_char_byte_col(line))
      if last.row and last.row > 0 then
        local r2 = last.row - pos[1] - 1
        if r1 == r2 then
          local edge = (last.endcol or last.col) - pos[2] - 1
          if r1 >= 0 and r1 < height then edges[r1] = math.max(edges[r1], edge) end
        else
          for row = math.max(0, r1), math.min(height - 1, r2 - 1) do edges[row] = width - 1 end
          if r2 >= 0 and r2 < height then
            edges[r2] = math.max(edges[r2], (last.endcol or last.col) - pos[2] - 1)
          end
        end
      elseif r1 >= 0 and r1 < height then
        for row = r1, height - 1 do edges[row] = width - 1 end
      end
    end
  end

  local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buf, -1, { top - 1, 0 }, { bottom - 1, -1 }, {
    details = true,
    type = "virt_text",
  })
  if ok then
    for _, mark in ipairs(marks) do
      local lnum = mark[2] + 1
      local byte_col = mark[3] + 1
      local details = mark[4] or {}
      local text_width = virtual_text_width(details.virt_text)
      if text_width > 0 then
        local screen = vim.fn.screenpos(win, lnum, byte_col)
        if not screen.row or screen.row <= 0 then
          local line = (vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or "")
          screen = vim.fn.screenpos(win, lnum, last_char_byte_col(line))
        end
        if screen.row and screen.row > 0 then
          local row = screen.row - pos[1] - 1
          if row >= 0 and row < height then
            local mode = details.virt_text_pos or "eol"
            local start_col = screen.col - pos[2] - 1
            local edge
            if mode == "right_align" then
              edge = width - 1
            elseif mode == "win_col" and details.virt_text_win_col ~= nil then
              edge = details.virt_text_win_col + text_width - 1
            elseif mode == "inline" then
              edge = math.max((edges[row] or -1) + text_width, start_col + text_width - 1)
            elseif mode == "overlay" then
              edge = start_col + text_width - 1
            else
              edge = (edges[row] or -1) + text_width + 1
            end
            edges[row] = math.max(edges[row] or -1, math.min(width - 1, edge))
          end
        end
      end
    end
  end
  return edges
end

local function area_safe(edges, x, y, sprite_w, sprite_h, margin)
  if x < margin or y < margin then return false end
  for row = y, y + sprite_h - 1 do
    if (edges[row] or -1) >= x - margin then return false end
  end
  return true
end

local function placement_context(win, avatar, opts)
  if not valid_win(win) then return nil end
  opts = opts or {}
  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  local sprite_w, sprite_h = avatar.width, render_height(avatar)
  local margin = opts.margin or 1

  if width < (opts.min_width or 1) or height < (opts.min_height or 1) then return nil end
  if sprite_w + margin * 2 >= width or sprite_h + margin * 2 >= height then return nil end

  local x = width - sprite_w - margin
  local edges = right_edges(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local cursor_screen = vim.fn.screenpos(win, cursor[1], cursor[2] + 1)
  local win_pos = vim.api.nvim_win_get_position(win)
  local desired = height - sprite_h - margin
  if cursor_screen.row and cursor_screen.row > 0 then
    desired = math.min(desired, math.max(margin, cursor_screen.row - win_pos[1] + 1))
  end

  local ctx = {
    win = win,
    width = width,
    height = height,
    sprite_w = sprite_w,
    sprite_h = sprite_h,
    margin = margin,
    x = x,
    edges = edges,
    desired = desired,
  }
  state.safety_context = ctx
  state.safety_opts = opts
  return ctx
end

local function position_safe(ctx, position)
  local q = quantize_position(position)
  if q.x + ctx.sprite_w + ctx.margin > ctx.width or q.y + ctx.sprite_h + ctx.margin > ctx.height then
    return false
  end
  return area_safe(ctx.edges, q.x, q.y, ctx.sprite_w, ctx.sprite_h, ctx.margin)
end

local function actual_position_safe(parent, avatar, position)
  if not position or not valid_win(parent) then return false end
  local ctx = state.safety_context
  local sprite_h = render_height(avatar)
  if not ctx or ctx.win ~= parent or ctx.sprite_w ~= avatar.width or ctx.sprite_h ~= sprite_h then
    ctx = placement_context(parent, avatar, state.safety_opts or {})
  end
  return ctx ~= nil and position_safe(ctx, position)
end

local function invalidate_safety()
  state.safety_context = nil
end

local safety_group = vim.api.nvim_create_augroup("FamiliarRenderSafety", { clear = true })
vim.api.nvim_create_autocmd(
  { "BufEnter", "DiagnosticChanged", "TextChanged", "TextChangedI", "TextChangedP", "WinResized", "WinScrolled" },
  {
    group = safety_group,
    callback = invalidate_safety,
  }
)

function M.find_safe_positions(win, avatar, opts)
  local ctx = placement_context(win, avatar, opts)
  if not ctx then return {} end

  local candidates = {}
  for row = ctx.margin, ctx.height - ctx.sprite_h - ctx.margin do
    if area_safe(ctx.edges, ctx.x, row, ctx.sprite_w, ctx.sprite_h, ctx.margin) then
      candidates[#candidates + 1] = {
        x = ctx.x,
        y = row,
        score = math.abs(row - ctx.desired),
      }
    end
  end
  table.sort(candidates, function(a, b) return a.score < b.score end)

  local max_candidates = opts.max_candidates or #candidates
  while #candidates > max_candidates do table.remove(candidates) end
  return candidates
end

function M.find_safe_position(win, avatar, opts)
  local candidates = M.find_safe_positions(win, avatar, opts)
  return candidates[1]
end

function M.is_safe_position(win, avatar, opts, position)
  if not position then return false end
  local ctx = placement_context(win, avatar, opts)
  if not ctx then return false end
  return position_safe(ctx, position)
end

function M.is_safe_path(win, avatar, opts, from, target)
  if not from or not target then return false end
  local ctx = placement_context(win, avatar, opts)
  if not ctx then return false end

  local dx, dy = target.x - from.x, target.y - from.y
  local steps = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy))))
  for step = 0, steps do
    local progress = step / steps
    if not position_safe(ctx, {
      x = from.x + dx * progress,
      y = from.y + dy * progress,
    }) then
      return false
    end
  end
  return true
end

function M.draw(parent, avatar, frame_name, position)
  if not position or not valid_win(parent) then
    M.hide()
    return false
  end
  local frame = avatar.frames[frame_name]
  if not frame then return false end

  if not actual_position_safe(parent, avatar, position) then
    close_surface()
    M.clear_trail()
    state.stats.safety_suppressed = state.stats.safety_suppressed + 1
    return false
  end

  define_base_highlight()
  position_surface(parent, avatar, position)

  local content_key = table.concat({ avatar.id, avatar_kind(avatar), frame_name }, ":")
  if state.last_content_key == content_key and valid_win(state.win) then return true end

  local lines, spans = frame_lines(avatar, frame)
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
  state.last_content_key = content_key
  state.stats.content_updates = state.stats.content_updates + 1
  return true
end

local function dim_hex(color, factor)
  local r, g, b = color:match("^#(%x%x)(%x%x)(%x%x)$")
  if not r then return color end
  local function channel(v)
    return math.max(0, math.min(255, math.floor(tonumber(v, 16) * factor + 0.5)))
  end
  return ("#%02X%02X%02X"):format(channel(r), channel(g), channel(b))
end

local function trail_group(color, level)
  local key = color .. ":" .. level
  if state.trail.highlights[key] then return state.trail.highlights[key] end
  local factors = { 1.0, 0.72, 0.48, 0.30 }
  local group = "FamiliarTrail_" .. color:gsub("[^%w]", "") .. "_" .. level
  vim.api.nvim_set_hl(0, group, { fg = dim_hex(color, factors[level] or 0.3) })
  state.trail.highlights[key] = group
  return group
end

local function ensure_trail_slot(index, parent)
  local slot = state.trail.pool[index]
  if slot and vim.api.nvim_buf_is_valid(slot.buf) and valid_win(slot.win) and slot.parent == parent then return slot end

  if slot then
    if valid_win(slot.win) then pcall(vim.api.nvim_win_close, slot.win, true) end
    if slot.buf and vim.api.nvim_buf_is_valid(slot.buf) then pcall(vim.api.nvim_buf_delete, slot.buf, { force = true }) end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "win",
    win = parent,
    row = 0,
    col = 0,
    width = 1,
    height = 1,
    style = "minimal",
    focusable = false,
    mouse = false,
    noautocmd = true,
    zindex = 44,
    hide = true,
  })
  vim.wo[win].winblend = 100
  vim.wo[win].winhighlight =
    "Normal:FamiliarTransparent,NormalFloat:FamiliarTransparent,EndOfBuffer:FamiliarTransparent"
  slot = { buf = buf, win = win, parent = parent, key = nil, pos = nil }
  state.trail.pool[index] = slot
  return slot
end

local function filter_safe_points(parent, samples, opts)
  if not valid_win(parent) then return {} end
  opts = opts or {}
  local width = vim.api.nvim_win_get_width(parent)
  local height = vim.api.nvim_win_get_height(parent)
  local margin = opts.margin or 0
  local edges = right_edges(parent)
  local safe = {}
  for _, sample in ipairs(samples or {}) do
    local q = quantize_position(sample)
    if q.x + 1 + margin <= width
      and q.y + 1 + margin <= height
      and area_safe(edges, q.x, q.y, 1, 1, margin)
    then
      safe[#safe + 1] = sample
    end
  end
  return safe
end

function M.draw_trail(parent, avatar, samples, opts)
  if not valid_win(parent) then return end
  samples = filter_safe_points(parent, samples, opts)
  local color = avatar.palette.effect or avatar.palette.outline or "#888888"

  for index, sample in ipairs(samples) do
    local slot = ensure_trail_slot(index, parent)
    local level = math.max(1, math.min(4, sample.level or 1))
    local key = tostring(sample.glyph) .. ":" .. level
    if slot.key ~= key then
      vim.bo[slot.buf].modifiable = true
      vim.api.nvim_buf_set_lines(slot.buf, 0, -1, false, { sample.glyph })
      vim.api.nvim_buf_clear_namespace(slot.buf, state.ns, 0, -1)
      vim.api.nvim_buf_add_highlight(slot.buf, state.ns, trail_group(color, level), 0, 0, -1)
      vim.bo[slot.buf].modifiable = false
      slot.key = key
      state.stats.trail_updates = state.stats.trail_updates + 1
    end

    local q = quantize_position(sample)
    local pos_key = q.x .. ":" .. q.y
    if slot.pos ~= pos_key then
      vim.api.nvim_win_set_config(slot.win, {
        relative = "win",
        win = parent,
        row = q.y,
        col = q.x,
        width = 1,
        height = 1,
        hide = false,
      })
      slot.pos = pos_key
    else
      pcall(vim.api.nvim_win_set_config, slot.win, { hide = false })
    end
  end

  for index = #samples + 1, #state.trail.pool do
    local slot = state.trail.pool[index]
    if slot and valid_win(slot.win) then pcall(vim.api.nvim_win_set_config, slot.win, { hide = true }) end
  end
end

function M.clear_trail()
  for _, slot in ipairs(state.trail.pool) do
    if slot and valid_win(slot.win) then pcall(vim.api.nvim_win_set_config, slot.win, { hide = true }) end
  end
end

function M.hide()
  close_surface()
  M.clear_trail()
  state.last_content_key = nil
end

function M.reset_surface()
  M.hide()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.buf = nil
  state.highlights = {}
  state.last_content_key = nil
  state.last_position_key = nil
  state.safety_context = nil
  state.safety_opts = nil
end

function M.stop()
  M.reset_surface()
  for _, slot in ipairs(state.trail.pool) do
    if slot and valid_win(slot.win) then pcall(vim.api.nvim_win_close, slot.win, true) end
    if slot and slot.buf and vim.api.nvim_buf_is_valid(slot.buf) then
      pcall(vim.api.nvim_buf_delete, slot.buf, { force = true })
    end
  end
  state.trail.pool = {}
  state.trail.highlights = {}
end

function M.stats()
  return vim.deepcopy(state.stats)
end

function M._frame_lines(avatar, frame_name)
  return frame_lines(avatar, assert(avatar.frames[frame_name]))
end

function M._render_height(avatar)
  return render_height(avatar)
end

M._filter_safe_points = filter_safe_points
M._right_edges = right_edges
M._actual_position_safe = actual_position_safe
M._invalidate_safety = invalidate_safety

return M