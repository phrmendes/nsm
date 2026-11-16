local mappings = {
  { name = "switch", desc = "Switch session" },
  { name = "kill", desc = "Stop session" },
  { name = "new", desc = "Start session for a directory" },
}

vim.iter(mappings):each(function(mapping)
  vim.keymap.set("n", "<Plug>(nsm-" .. mapping.name .. ")", function() require("nsm")[mapping.name]() end, {
    desc = mapping.desc,
  })
end)

vim.api.nvim_create_user_command("Nsm", function(opts) require("nsm").command(opts.args) end, {
  desc = "Switch the current session",
  nargs = "?",
  complete = function() return require("nsm").complete() end,
})
