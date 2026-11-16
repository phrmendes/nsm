local test = require("mini.test")
local eq = test.expect.equality

local child = test.new_child_neovim()

local T = test.new_set({
  hooks = {
    pre_case = function() child.restart({ "-u", "scripts/init.lua" }) end,
    post_once = child.stop,
  },
})

T["buffers"] = test.new_set()

T["buffers"]["returns listed names, shortened, without unnamed buffers"] = function()
  local result = child.lua([[
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "a" }, dir .. "/a.txt")
    vim.fn.writefile({ "b" }, dir .. "/b.txt")

    vim.cmd.cd(dir)
    vim.cmd.edit(dir .. "/a.txt")
    vim.cmd.edit(dir .. "/b.txt")

    local unlisted = vim.fn.bufadd(dir .. "/c.txt")
    vim.fn.bufload(unlisted)
    vim.cmd.enew()

    local names = require("nsm").buffers()
    vim.fn.delete(dir, "rf")

    return names
  ]])

  eq(result, "a.txt\nb.txt")
end

T["switch"] = test.new_set()

T["switch"]["opens the overlay with the current session"] = function()
  local calls = child.lua([[
    local captured = {}

    vim.system = function(command, opts) table.insert(captured, { command = command, detach = opts.detach }) end
    vim.env.KITTY_LISTEN_ON = "unix:/tmp/kitty"
    vim.env.NSM_SESSION = "demo"

    require("nsm").switch()

    return captured
  ]])

  eq(calls, {
    {
      command = {
        "kitten",
        "@",
        "launch",
        "--type=overlay",
        "--cwd=current",
        "--env",
        "NSM_SESSION=demo",
        "nsm",
        "switch",
      },
      detach = true,
    },
  })
end

T["switch"]["omits the session env when none is set"] = function()
  local calls = child.lua([[
    local captured = {}

    vim.system = function(command) table.insert(captured, command) end
    vim.env.KITTY_LISTEN_ON = "unix:/tmp/kitty"
    vim.env.NSM_SESSION = nil

    require("nsm").switch()

    return captured
  ]])

  eq(calls, { { "kitten", "@", "launch", "--type=overlay", "--cwd=current", "nsm", "switch" } })
end

T["switch"]["warns and does nothing outside kitty"] = function()
  local result = child.lua([[
    local calls, notified = 0, nil

    vim.system = function() calls = calls + 1 end
    vim.notify = function(message, level) notified = { message = message, level = level } end
    vim.env.KITTY_LISTEN_ON = nil

    require("nsm").switch()

    return { calls = calls, level = notified and notified.level }
  ]])

  eq(result.calls, 0)
  eq(result.level, vim.log.levels.WARN)
end

T["setup"] = test.new_set()

T["setup"]["custom key replaces the default mapping"] = function()
  child.lua([[ require("nsm").setup({ keymap = "<leader>s" }) ]])

  eq(child.lua_get("vim.fn.maparg('<leader>w', 'n')"), "")
  eq(child.lua_get("vim.fn.maparg('<leader>s', 'n', false, true).rhs"), "<Plug>(nsm-switch)")
end

T["setup"]["keeps a mapping that the user owns"] = function()
  local kept = child.lua([[
    vim.keymap.set("n", "<leader>w", function() end)
    require("nsm").setup({ keymap = "<leader>s" })

    return vim.fn.maparg("<leader>w", "n", false, true).callback ~= nil
  ]])

  eq(kept, true)
end

T["setup"]["removes the plugin mapping with keymap false"] = function()
  child.lua([[ require("nsm").setup({ keymap = false }) ]])

  eq(child.lua_get("vim.fn.maparg('<leader>w', 'n')"), "")
  eq(child.lua_get("vim.fn.maparg('<Plug>(nsm-switch)', 'n') ~= ''"), true)
end

return T
