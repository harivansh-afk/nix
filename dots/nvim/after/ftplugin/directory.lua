local buf = vim.api.nvim_get_current_buf()

local function dir() return vim.api.nvim_buf_get_name(buf) end

local function entry()
  local line = vim.api.nvim_get_current_line():gsub("%z", "\n")
  if line == "" then return nil end
  return vim.fs.joinpath(dir(), (line:gsub("/$", "")))
end

local function reload() vim.cmd [[execute "normal \<Plug>(nvim-dir-reload)"]] end

local function resolve(name) return name:sub(1, 1) == "/" and name or vim.fs.joinpath(dir(), name) end

local function ask(prompt, default, fn)
  vim.ui.input({ prompt = prompt, default = default }, function(input)
    if input and input ~= "" then fn(input) end
  end)
end

local function map(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc }) end

map("%", function()
  ask("new file: ", nil, function(name) vim.cmd.edit(vim.fn.fnameescape(resolve(name))) end)
end, "new file")

map("d", function()
  ask("new directory: ", nil, function(name)
    vim.fn.mkdir(resolve(name), "p")
    reload()
  end)
end, "new directory")

map("r", function()
  local from = entry()
  if not from then return end
  ask("move to: ", vim.fs.basename(from), function(name)
    local to = resolve(name)
    vim.fn.mkdir(vim.fs.dirname(to), "p")
    if vim.fn.rename(from, to) ~= 0 then return vim.notify("rename failed: " .. from, vim.log.levels.ERROR) end
    reload()
  end)
end, "rename or move")

map("D", function()
  local path = entry()
  if not path or vim.fn.confirm("Delete " .. vim.fs.basename(path) .. "?", "&Yes\n&No", 2) ~= 1 then return end
  if vim.fn.delete(path, "rf") ~= 0 then return vim.notify("delete failed: " .. path, vim.log.levels.ERROR) end
  reload()
end, "delete")

local function pick(name)
  require("lz.n").trigger_load "mini.pick"
  MiniPick.builtin[name](nil, { source = { cwd = dir() } })
end

map("<C-f>", function() pick "files" end, "files in this directory")
map("<C-s>", function() pick "grep_live" end, "grep in this directory")
