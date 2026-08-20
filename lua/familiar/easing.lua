local M = {}

local funcs = {
  linear = function(t)
    return t
  end,
  quad = function(t)
    return 1 - (1 - t) ^ 2
  end,
  out_quad = function(t)
    return 1 - (1 - t) ^ 2
  end,
  cubic = function(t)
    return 1 - (1 - t) ^ 3
  end,
  out_cubic = function(t)
    return 1 - (1 - t) ^ 3
  end,
  quart = function(t)
    return 1 - (1 - t) ^ 4
  end,
  out_quart = function(t)
    return 1 - (1 - t) ^ 4
  end,
}

function M.names()
  local names = vim.tbl_keys(funcs)
  table.sort(names)
  return names
end

function M.apply(name, t)
  local fn = funcs[name]
  if not fn then
    error(("familiar.nvim: unknown easing %q"):format(tostring(name)))
  end
  t = math.max(0, math.min(1, t))
  return fn(t)
end

return M
