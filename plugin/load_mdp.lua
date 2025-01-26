vim.api.nvim_create_user_command("Mdp", function()
    require("mdp").mdp { bufnr = 0 }
end, {
    desc = "Start markdown presentation from current buffer",
})
