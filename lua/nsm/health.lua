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
  report(
    "Neovim 0.12 :connect",
    vim.fn.has("nvim-0.12") == 1 and vim.fn.exists(":connect") == 2 and "available" or nil,
    "Upgrade to Neovim 0.12 to switch sessions in place.",
    "error"
  )
  report("fzf", vim.fn.exepath("fzf"), "Install fzf for the terminal picker.", "warn")
  report("zoxide", vim.fn.exepath("zoxide"), "Install zoxide to list recent directories.", "warn")
end

return health
