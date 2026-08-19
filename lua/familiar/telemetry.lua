local M = {}

local state = {
  group = nil,
  last_activity = vim.uv.now(),
  typing_until = 0,
  switches = {},
  on_event = nil,
  config = nil,
}

local function now()
  return vim.uv.now()
end

local function touch(typing)
  state.last_activity = now()
  if typing then state.typing_until = state.last_activity + 900 end
end

local function prune_switches()
  local cutoff = now() - 10000
  local keep = {}
  for _, stamp in ipairs(state.switches) do
    if stamp >= cutoff then keep[#keep + 1] = stamp end
  end
  state.switches = keep
end

local function emit(kind, args)
  if state.on_event then state.on_event(kind, args or {}) end
end

local function truncate_chars(text, max_chars)
  if max_chars <= 0 then return "" end
  if vim.fn.strchars(text) <= max_chars then return text end
  return vim.fn.strcharpart(text, 0, max_chars)
end

local function text_context(buf, cursor_row, config)
  local brain = config.brain or {}
  local opts = brain.context or {}
  if not brain.enabled or opts.include_buffer_text == false then
    return { current_line = "", before = {}, after = {} }
  end

  local total_budget = math.max(0, opts.max_total_chars or 0)
  local line_budget = math.max(0, opts.max_line_chars or 0)
  if total_budget == 0 or line_budget == 0 then
    return { current_line = "", before = {}, after = {} }
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  local before_n = math.max(0, opts.lines_before or 0)
  local after_n = math.max(0, opts.lines_after or 0)
  local first = math.max(1, cursor_row - before_n)
  local last = math.min(line_count, cursor_row + after_n)
  local raw = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)

  local remaining = total_budget
  local function take(line)
    if remaining <= 0 then return "" end
    local capped = truncate_chars(line, math.min(line_budget, remaining))
    remaining = remaining - vim.fn.strchars(capped)
    return capped
  end

  local current_index = cursor_row - first + 1
  local current_line = take(raw[current_index] or "")

  -- Spend the remaining budget on the nearest surrounding lines first. This
  -- preserves semantic locality if a very long buffer line consumes most of
  -- the configured context budget.
  local before_reversed = {}
  for index = current_index - 1, 1, -1 do
    local line = take(raw[index] or "")
    if line == "" and remaining <= 0 then break end
    before_reversed[#before_reversed + 1] = line
  end
  local before = {}
  for index = #before_reversed, 1, -1 do before[#before + 1] = before_reversed[index] end

  local after = {}
  for index = current_index + 1, #raw do
    local line = take(raw[index] or "")
    if line == "" and remaining <= 0 then break end
    after[#after + 1] = line
  end

  return { current_line = current_line, before = before, after = after }
end

function M.setup(config, on_event)
  state.config = config
  state.on_event = on_event
  state.group = vim.api.nvim_create_augroup("FamiliarTelemetry", { clear = true })

  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = state.group,
    callback = function(args)
      touch(true)
      emit("typing", args)
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = state.group,
    callback = function(args)
      touch(false)
      emit("cursor_moved", args)
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = state.group,
    callback = function(args)
      touch(false)
      state.switches[#state.switches + 1] = now()
      prune_switches()
      emit("buffer_enter", args)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWritePost", "DiagnosticChanged", "WinResized", "WinScrolled", "ModeChanged" }, {
    group = state.group,
    callback = function(args)
      if args.event ~= "WinScrolled" then touch(false) end
      emit(string.lower(args.event), args)
    end,
  })
end

function M.stop()
  if state.group then pcall(vim.api.nvim_del_augroup_by_id, state.group) end
  state.group = nil
  state.on_event = nil
end

function M.snapshot(config)
  local win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then return nil end
  local win_config = vim.api.nvim_win_get_config(win)
  if win_config.relative and win_config.relative ~= "" then return nil end

  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  if vim.bo[buf].buftype ~= "" then return nil end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local bounds = vim.api.nvim_win_call(win, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end)
  local top, bottom = bounds[1], bounds[2]
  local max_lines = config.telemetry.max_visible_lines or 120
  local last = math.min(bottom, top + max_lines - 1)
  local lines = vim.api.nvim_buf_get_lines(buf, top - 1, last, false)
  local widths = {}
  for _, line in ipairs(lines) do widths[#widths + 1] = vim.fn.strdisplaywidth(line) end

  local errors = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })
  local warnings = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.WARN })
  prune_switches()

  return {
    mode = vim.api.nvim_get_mode().mode,
    buffer = {
      id = buf,
      name = vim.api.nvim_buf_get_name(buf),
      filetype = vim.bo[buf].filetype,
      modified = vim.bo[buf].modified,
      line_count = vim.api.nvim_buf_line_count(buf),
    },
    viewport = {
      width = vim.api.nvim_win_get_width(win),
      height = vim.api.nvim_win_get_height(win),
      cursor_row = cursor[1],
      cursor_col = cursor[2],
      topline = top,
      botline = bottom,
      line_display_widths = widths,
    },
    diagnostics = { errors = errors, warnings = warnings },
    activity = {
      idle_ms = math.max(0, now() - state.last_activity),
      typing = now() < state.typing_until,
      buffer_switches_10s = #state.switches,
    },
    context = text_context(buf, cursor[1], config),
  }
end

M._text_context = text_context

return M
