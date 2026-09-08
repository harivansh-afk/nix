local canola_config = require "config.canola"

return {
  {
    "canola.nvim",
    cmd = "Canola",
    before = canola_config.setup_globals,
    after = canola_config.setup_integrations,
    keys = {
      { "-", "<cmd>Canola<cr>" },
      { "<leader>e", "<cmd>Canola<cr>" },
    },
  },
}
