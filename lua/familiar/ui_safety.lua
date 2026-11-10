local M = {}

local state = {
  ns = vim.api.nvim_create_namespace("FamiliarUiSafety"),
  running = false,
  on_change = nil,
  pending = {},
  signatures = {},
}

local function virtual_text_width(chunks)
  local width = 0
  for _, chunk in ipairs(chunks or {}) do width = width + vim.fn.strdisplaywidth(chunk[1] or "") end
  return width
end

local function signature(win)
  if not vim.api.nvim_win_is_valid(win) then return nil end
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative and cfg.relative ~= "" then return nil end

  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return nil end

  local bounds = vim.api.nvim_win_call(win, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end)
  local top, bottom = bounds[1], bounds[2]
  local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buf, -1, { top - 1, 0 }, { bottom - 1, -1 }, {
    details = true,
    type = "virt_text",
  })
  if not ok then return { buf = buf, value = "" } end

  local parts = {}
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    local width = virtual_text_width(details.virt_text)
    if width > 0 then
      parts[#parts + 1] = table.concat({
        tostring(mark[2] or 0),
        tostring(mark[3] or 0),
        tostring(details.virt_text_pos or "eol"),
        tostring(details.virt_text_win_col or ""),
        tostring(details.virt_text_hide == true),
        tostring(details.virt_text_repeat_linebreak == true),
        tostring(width),
      }, ":")
    end
  end

  return { buf = buf, value = table.concat(parts, "|") }
end

local function check(win)
  state.pending[win] = nil
  if not state.running or not vim.api.nvim_win_is_valid(win) then return end

  local current = signature(win)
  if not current then
    state.signatures[win] = nil
    return
  end

  local previous = state.signatures[win]
  state.signatures[win] = current
  if not previous or previous.buf ~= current.buf or previous.value == current.value then return end

  if state.on_change then
    state.on_change({
      event = "FamiliarUiChanged",
      buf = current.buf,
      win = win,
    })
  end
end

local function schedule_check(win)
  if not state.running or state.pending[win] then return end
  state.pending[win] = true
  vim.schedule(function() check(win) end)
end

function M.start(on_change)
  state.running = true
  state.on_change = on_change
  state.pending = {}
  state.signatures = {}

  vim.api.nvim_set_decoration_provider(state.ns, {
    on_win = function(_, win)
      if not state.running then return end
      if win == vim.api.nvim_get_current_win() then schedule_check(win) end
    end,
  })

  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(win) then
    vim.schedule(function()
      if not state.running then return end
      local current = signature(win)
      if current then state.signatures[win] = current end
    end)
  end
end

function M.stop()
  state.running = false
  state.on_change = nil
  state.pending = {}
  state.signatures = {}
  pcall(vim.api.nvim_set_decoration_provider, state.ns, {})
end

function M._tracked_signature(win)
  local tracked = state.signatures[win]
  return tracked and tracked.value or nil
end

M._signature = signature

return M
