local M = {}

function M.setup_globals()
  vim.g.canola_git = {}

  vim.g.canola = {
    buf = { buflisted = false, bufhidden = "wipe" },
    columns = { "git_status", "icon" },
    hidden = { enabled = false },
    highlights = { filename = {}, columns = true },
    save = "auto",
    extglob = true,
    delete = { wipe = false, recursive = true },
    float = { border = "single" },
    keymaps = {
      ["g?"] = { callback = "actions.show_help", mode = "n" },
      ["<CR>"] = "actions.select",
      ["<C-v>"] = { callback = "actions.select", opts = { vertical = true } },
      ["<C-x>"] = { callback = "actions.select", opts = { horizontal = true } },
      ["<C-p>"] = false, -- keep global <c-p> (pr: pick PR); preview via g? actions
      ["<C-c>"] = { callback = "actions.close", mode = "n" },
      ["-"] = { callback = "actions.parent", mode = "n" },
      ["g."] = { callback = "actions.toggle_hidden", mode = "n" },
      ["<C-t>"] = false,
    },
  }
end

function M.setup_integrations()
  vim.cmd.packadd "canola-collection"

  local augroup = vim.api.nvim_create_augroup("UserCanolaConfig", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "canola",
    callback = function(args)
      local bufnr = args.buf
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:find "^fugitive://" then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.bo[bufnr].syntax = "fugitive"
            vim.bo[bufnr].filetype = "fugitive"
          end
        end)
        return
      end

      vim.api.nvim_create_autocmd("BufLeave", {
        group = augroup,
        buffer = bufnr,
        once = true,
        callback = function()
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(bufnr) and not vim.b[bufnr].canola_ready then
              vim.api.nvim_buf_delete(bufnr, { force = true })
            end
          end)
        end,
      })

      local function pick(name)
        require("lz.n").trigger_load "mini.pick"
        MiniPick.builtin[name](nil, { source = { cwd = require("canola").get_current_dir(bufnr) } })
      end

      vim.keymap.set("n", "<C-f>", function() pick "files" end, { buffer = bufnr, desc = "files in canola dir" })
      vim.keymap.set("n", "<C-s>", function() pick "grep_live" end, { buffer = bufnr, desc = "grep in canola dir" })
    end,
  })
end

return M
