local M = {}

M.defaults = {
  enabled = true,
  debug = false,
  avatar = "fox",
  core = {
    enabled = true,
    bin = nil,
  },
  render = {
    frame_ms = 125,
    margin = 1,
    min_width = 48,
    min_height = 12,
    move_step = 2,
    warp_distance = 32,
  },
  telemetry = {
    snapshot_ms = 1200,
    max_visible_lines = 120,
  },
}

function M.resolve(opts)
  opts = opts or {}
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
end

return M
