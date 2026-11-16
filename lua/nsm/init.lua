--- *nsm.nvim* Neovim Server Manager
---
--- Open the session picker for the detached Neovim servers that nsm keeps.
---
--- `:Nsm` and the `<Plug>(nsm-switch)` mapping switch the current UI to the
--- chosen session with `:connect`.
---
---@tag nsm
---@tag :Nsm
---@tag <Plug>(nsm-switch)

---@class nsm.Config
---@field keymap string|false|nil Keymap for the session picker. Defaults to "<leader>w". Use false for no mapping.

local nsm = {}
local mapped

--- Strip the ANSI colour codes from a CLI message.
---
---@param text string|nil
---@return string
---@private
local function strip_ansi(text) return (text or ""):gsub("\27%[[%d;]*m", "") end

--- Run a command and return its trimmed stdout, or notify its failure.
---
---@param command string[]
---@return string|nil
---@private
local function run(command)
  local result = vim.system(command, { text = true }):wait()
  local stderr = (result.stderr or ""):gsub("%s+$", "")

  if result.code ~= 0 then
    local fallback = "`" .. table.concat(command, " ") .. "` failed"
    vim.notify(strip_ansi(stderr ~= "" and stderr or fallback), vim.log.levels.ERROR)
    return nil
  end

  return (result.stdout or ""):gsub("%s+$", "")
end

--- Return the name of the row, or its path when it has no session.
---
---@param item table
---@return string
---@private
local function get_target(item)
  if item.name and item.name ~= vim.NIL and item.name ~= "" then return item.name end
  return item.path
end

--- Ask for a session or directory with `vim.ui.select`.
---
---@param on_choice fun(item: table)
---@private
local function pick(on_choice)
  local output = run({ "nsm", "pick" })
  if not output then return end

  local ok, items = pcall(vim.json.decode, output)
  if not ok or type(items) ~= "table" then
    vim.notify("nsm returned invalid picker data", vim.log.levels.ERROR)
    return
  end

  if #items == 0 then
    vim.notify("There is nothing to pick. Start a session with `nsm new <name>`.", vim.log.levels.WARN)
    return
  end

  vim.ui.select(items, {
    prompt = "nsm> ",
    format_item = function(item) return item.label end,
  }, function(item)
    if item then on_choice(item) end
  end)
end

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

--- Attach the current UI to the Neovim server at `address`.
---
---@param address string
function nsm.connect(address) vim.cmd({ cmd = "connect", args = { address } }) end

--- Open the picker and switch the current UI to the chosen session.
---
--- Start the chosen session when it is stopped, then detach the current UI from
--- its server and attach it to the chosen server with `:connect`.
function nsm.switch()
  pick(function(item)
    local socket = run({ "nsm", "start", get_target(item) })
    if socket and socket ~= "" then nsm.connect(socket) end
  end)
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
