local o = vim.o

o.number = true
o.relativenumber = true

o.tabstop = 2
o.shiftwidth = 2
o.expandtab = true
o.breakindent = true

o.ignorecase = true
o.smartcase = true

o.scrolloff = 8
o.signcolumn = "number"
o.wrap = false
o.laststatus = 3

o.splitbelow = true
o.splitright = true

o.swapfile = false
o.undofile = true
o.cmdheight = 1

o.winborder = "rounded"
o.pumborder = "rounded"
o.pummaxwidth = 60
o.smoothscroll = true
o.scrolloffpad = 1
o.cursorline = true
o.cursorlineopt = "number"
vim.opt.fillchars:append { eob = " ", fold = " " }
vim.opt.diffopt:append "inline:word"
vim.opt.shortmess:append "u"

o.foldmethod = "expr"
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
o.foldtext = ""
o.foldlevelstart = 99

o.updatetime = 250
o.clipboard = "unnamedplus"
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "fuzzy", "popup" }

local has_clip_tool = vim.fn.has "mac" == 1
  or (vim.env.WAYLAND_DISPLAY and vim.fn.executable "wl-copy" == 1)
  or (vim.env.DISPLAY and (vim.fn.executable "xclip" == 1 or vim.fn.executable "xsel" == 1))
if not has_clip_tool then
  local cache = { ["+"] = {}, ["*"] = {} }
  local function copy(reg)
    return function(lines)
      cache[reg] = lines
      local seq = ("\027]52;c;%s\027\\"):format(vim.base64.encode(table.concat(lines, "\n")))
      pcall(vim.api.nvim_ui_send, seq)
    end
  end
  local function paste(reg)
    return function() return cache[reg] end
  end
  vim.g.clipboard = {
    name = "osc52-write",
    copy = { ["+"] = copy "+", ["*"] = copy "*" },
    paste = { ["+"] = paste "+", ["*"] = paste "*" },
  }
end

vim.cmd.packadd "nohlsearch"
vim.cmd.packadd "nvim.undotree"
vim.cmd.packadd "nvim.difftool"

vim.diagnostic.config { virtual_lines = { current_line = true }, severity_sort = true }
