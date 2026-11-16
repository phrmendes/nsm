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

T["switch"]["starts the chosen session and attaches the current UI"] = function()
  local calls = child.lua([[
    local captured = {}
    local rows = '[{"label":"🟢 work  ~/work","name":"work","path":"/home/ana/work","source":"running"}]'

    vim.system = function(command)
      table.insert(captured, { command = command })

      return {
        code = 0,
        stdout = command[2] == "pick" and rows or "/state/nsm/work.sock\n",
        stderr = "",
        wait = function(self) return self end,
      }
    end

    vim.ui.select = function(items, opts, on_choice)
      table.insert(captured, { prompt = opts.prompt, labels = vim.tbl_map(function(item) return item.label end, items) })
      on_choice(items[1], 1)
    end

    local nsm = require("nsm")
    nsm.connect = function(address) table.insert(captured, { connect = address }) end
    nsm.switch()

    return captured
  ]])

  eq(calls, {
    { command = { "nsm", "pick" } },
    { prompt = "nsm> ", labels = { "🟢 work  ~/work" } },
    { command = { "nsm", "start", "work" } },
    { connect = "/state/nsm/work.sock" },
  })
end

T["switch"]["starts a directory that has no session yet"] = function()
  local calls = child.lua([[
    local captured = {}
    local rows = '[{"label":"📁 ~/project","name":null,"path":"/home/ana/project","source":"directory"}]'

    vim.system = function(command)
      table.insert(captured, command)

      return {
        code = 0,
        stdout = command[2] == "pick" and rows or "/state/nsm/project.sock\n",
        stderr = "",
        wait = function(self) return self end,
      }
    end

    vim.ui.select = function(items, _, on_choice) on_choice(items[1], 1) end

    local nsm = require("nsm")
    nsm.connect = function() end
    nsm.switch()

    return captured
  ]])

  eq(calls, {
    { "nsm", "pick" },
    { "nsm", "start", "/home/ana/project" },
  })
end

T["switch"]["cancelling the picker starts and connects nothing"] = function()
  local calls = child.lua([[
    local captured = {}

    vim.system = function(command)
      table.insert(captured, command)

      return { code = 0, stdout = "[{\"label\":\"🟢 work\",\"name\":\"work\",\"path\":\"/w\"}]", stderr = "", wait = function(self) return self end }
    end

    vim.ui.select = function(_, _, on_choice) on_choice(nil, nil) end

    local nsm = require("nsm")
    nsm.connect = function() table.insert(captured, "connected") end
    nsm.switch()

    return captured
  ]])

  eq(calls, { { "nsm", "pick" } })
end

T["switch"]["passes zoxide rows to vim.ui.select"] = function()
  local result = child.lua([[
    local captured = { commands = {} }
    local rows = '[{"label":"📁 ~/project","name":null,"path":"/home/ana/project","source":"directory"},{"label":"[Z] 📁 ~/recent","name":null,"path":"/home/ana/recent","source":"zoxide"}]'

    vim.system = function(command)
      table.insert(captured.commands, command)
      return { code = 0, stdout = command[2] == "pick" and rows or "/state/nsm/project.sock", stderr = "", wait = function(self) return self end }
    end

    vim.ui.select = function(items, opts, on_choice, start_opts)
      captured.sources = vim.tbl_map(function(item) return item.source end, items)
      captured.zoxide_label = items[2].label
      captured.prompt = opts.prompt
      captured.extra_opts = start_opts
      on_choice(items[1], 1)
    end

    local nsm = require("nsm")
    nsm.connect = function() end
    nsm.switch()

    return captured
  ]])

  eq(result.sources, { "directory", "zoxide" })
  eq(result.zoxide_label, "[Z] 📁 ~/recent")
  eq(result.prompt, "nsm> ")
  eq(result.extra_opts, nil)
end

T["switch"]["notifies when the pick command fails"] = function()
  local message = child.lua([[
    local notified

    vim.system = function()
      return { code = 1, stdout = "", stderr = "\27[31m[E]\27[0m Cannot query the sessions", wait = function(self) return self end }
    end

    vim.notify = function(text) notified = text end
    require("nsm").switch()

    return notified
  ]])

  eq(message, "[E] Cannot query the sessions")
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
