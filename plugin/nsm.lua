vim.api.nvim_create_user_command("Nsm", function() require("nsm").switch() end, { desc = "Open the session picker", nargs = 0 })

vim.keymap.set("n", "<Plug>(nsm-switch)", function() require("nsm").switch() end, { desc = "Switch session" })
