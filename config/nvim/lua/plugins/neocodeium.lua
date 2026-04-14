vim.pack.add({
  "https://github.com/monkoose/neocodeium",
}, { load = function() end })

return {
  "monkoose/neocodeium",
  event = "InsertEnter",
  after = function()
    local neocodeium = require "neocodeium"
    neocodeium.setup()

    vim.keymap.set("i", "<Right>", neocodeium.accept)
    vim.keymap.set("i", "<A-w>", neocodeium.accept_word)
    vim.keymap.set("i", "<A-a>", neocodeium.accept_line)
    vim.keymap.set("i", "<A-e>", neocodeium.cycle_or_complete)
    vim.keymap.set("i", "<A-r>", function() neocodeium.cycle_or_complete(-1) end)
    vim.keymap.set("i", "<A-c>", neocodeium.clear)
  end,
}
