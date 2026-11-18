--- Health check for nsm.
---
--- Run it with `:checkhealth nsm`. It checks that these are available:
---
--- - `nsm`, `bash`, and Neovim 0.12 `:connect`. A missing one is an error.
--- - `fzf`, `git`, and `zoxide`. A missing one is a warning.
---
---@tag nsm-health

local h = vim.health

local health = {}

---@param name string
---@param value string|nil
---@param hint string
---@param level string
---@private
local function report(name, value, hint, level)
  if value == nil or value == "" then
    h[level](name .. " is not available", { hint })
    return
  end

  h.ok(name .. ": " .. value)
end

--- Check that `nsm`, `bash`, Neovim 0.12, `fzf`, `git`, and `zoxide` are available.
---
---@private
function health.check()
  h.start("nsm")

  report("nsm", vim.fn.exepath("nsm"), "Install the nsm CLI and put it on PATH.", "error")
  report(
    "Neovim 0.12 :connect",
    vim.version.ge(vim.version(), { 0, 12 }) and vim.fn.exists(":connect") == 2 and "available" or nil,
    "Upgrade to Neovim 0.12 to switch sessions in place.",
    "error"
  )
  report("bash", vim.fn.exepath("bash"), "Install bash to start the servers.", "error")
  report("fzf", vim.fn.exepath("fzf"), "Install fzf for the terminal picker.", "warn")
  report("git", vim.fn.exepath("git"), "Install git to name a session after its repository root.", "warn")
  report("zoxide", vim.fn.exepath("zoxide"), "Install zoxide to list recent directories.", "warn")
end

return health
