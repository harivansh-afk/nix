local o, opt = vim.o, vim.opt

o.number = true
o.relativenumber = true

o.tabstop = 2
o.shiftwidth = 2
o.expandtab = true
o.smartindent = true
o.breakindent = true

o.ignorecase = true
o.smartcase = true
o.hlsearch = false
o.incsearch = true

o.termguicolors = true
o.scrolloff = 8
o.signcolumn = 'yes'
o.wrap = false
o.showmode = false
o.laststatus = 3
o.cmdheight = 0

opt.fillchars = { vert = '|', fold = '-', foldsep = '|', diff = '-' }
opt.shortmess:append('S')

o.splitbelow = true
o.splitright = true

o.swapfile = false
o.backup = false
o.undofile = true
o.undodir = vim.fn.stdpath('data') .. '/undo'

o.foldlevel = 99
o.foldlevelstart = 99
o.foldenable = true

o.updatetime = 250
o.mouse = 'a'
o.clipboard = 'unnamedplus'
