if vim.g.loaded_copilot_cli then
  return
end
vim.g.loaded_copilot_cli = 1

local copilot_cli = require("copilot-cli")

vim.api.nvim_create_user_command("AISend", function()
  copilot_cli.send_prompt()
end, {
  desc = "Send prompt to AI CLI (copilot/qodercli) with placeholder support",
})

vim.api.nvim_create_user_command("AISelect", function()
  copilot_cli.select_target()
end, {
  desc = "Re-detect and select AI CLI instance",
})
