--- Health check for nsm.
---
--- Run it with `:checkhealth nsm`.
---
---@tag nsm-health

local h = vim.health or require("vim.health")

local health = {}

---@private
---@param name string
---@param value string|nil
---@param hint string
---@param level string
local function report(name, value, hint, level)
  if value == nil or value == "" then
    h[level](name .. " is not available", { hint })
    return
  end

  h.ok(name .. ": " .. value)
end

function health.check()
  h.start("nsm")

  report("nsm", vim.fn.exepath("nsm"), "Install the nsm CLI and put it on PATH.", "error")
end

return health
