-- agentdiff wiring: canonical RPC socket for agent-hook pokes + entry points.
-- The first nvim instance owns the socket; stale sockets from dead instances
-- are reclaimed. See lua/agentdiff.lua.

local sock = (os.getenv "XDG_CACHE_HOME" or vim.fs.normalize "~/.cache") .. "/nvim/agentdiff.sock"

vim.fn.mkdir(vim.fs.dirname(sock), "p")
if vim.uv.fs_stat(sock) then
  local ok, chan = pcall(vim.fn.sockconnect, "pipe", sock, { rpc = true })
  if ok and chan > 0 then
    vim.fn.chanclose(chan) -- live owner exists; this instance stays passive
  else
    vim.uv.fs_unlink(sock) -- stale socket from a dead instance
  end
end
if not vim.uv.fs_stat(sock) then pcall(vim.fn.serverstart, sock) end

vim.api.nvim_create_user_command("AgentDiff", function() require("agentdiff").open() end, {})
map("n", "<leader>aw", "<cmd>AgentDiff<cr>")
