if vim.g.loaded_cli_bridge then
  return
end
vim.g.loaded_cli_bridge = 1

local cli_bridge = require("cli-bridge")

vim.api.nvim_create_user_command("CliSend", function()
  cli_bridge.send_prompt()
end, {
  desc = "Send prompt to CLI (copilot/qodercli) with placeholder support",
})

vim.api.nvim_create_user_command("CliSelect", function()
  cli_bridge.select_target()
end, {
  desc = "Re-detect and select CLI instance",
})
