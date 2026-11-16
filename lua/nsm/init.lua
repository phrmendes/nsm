--- *nsm.nvim* Neovim Server Manager
---
--- Open the session picker for the detached Neovim servers that nsm keeps.
---
--- `:Nsm` and the `<Plug>(nsm-switch)` mapping open the picker in a kitty
--- overlay. They need `kitten` and the `KITTY_LISTEN_ON` variable.
---
---@tag nsm
---@tag :Nsm
---@tag <Plug>(nsm-switch)

---@class nsm.Config
---@field keymap string|false|nil Keymap for the session picker. Defaults to "<leader>w". Use false for no mapping.

local nsm = {}
local mapped

--- Return the listed buffer names, shortened against the home and the current directory.
---
--- The result is joined with a newline and used by the picker preview.
---
---@return string
function nsm.buffers()
  return vim
    .iter(vim.api.nvim_list_bufs())
    :filter(function(buffer) return vim.bo[buffer].buflisted end)
    :map(function(buffer) return vim.api.nvim_buf_get_name(buffer) end)
    :filter(function(name) return name ~= "" end)
    :map(function(name) return vim.fn.fnamemodify(name, ":~:.") end)
    :join("\n")
end

--- Open the session picker in a kitty overlay.
---
--- Forward the current session to the picker and run `nsm switch` detached.
--- Notify a warning and do nothing outside kitty.
function nsm.switch()
  if not vim.env.KITTY_LISTEN_ON then
    vim.notify("kitty remote control is not available", vim.log.levels.WARN)
    return
  end

  local command = { "kitten", "@", "launch", "--type=overlay", "--cwd=current" }

  if vim.env.NSM_SESSION then vim.list_extend(command, { "--env", "NSM_SESSION=" .. vim.env.NSM_SESSION }) end

  vim.list_extend(command, { "nsm", "switch" })
  vim.system(command, { detach = true })
end

--- Change the mapping of the plugin.
---
--- Leave the plugin defaults alone when `opts` is missing. Pass `keymap = false`
--- to remove the plugin mapping. A mapping that the user owns is never removed.
---
---@param opts nsm.Config|nil
function nsm.setup(opts)
  opts = opts or {}

  local keymap = opts.keymap
  if keymap == nil then return end

  if mapped then
    vim.keymap.del("n", mapped)
    mapped = nil
  end

  if vim.fn.maparg("<leader>w", "n", false, true).rhs == "<Plug>(nsm-switch)" then vim.keymap.del("n", "<leader>w") end

  if keymap then
    vim.keymap.set("n", keymap, "<Plug>(nsm-switch)", { desc = "Switch session" })
    mapped = keymap
  end
end

return nsm
