return {
    {
        'windwp/nvim-autopairs',
        config = true,
    },
    {
        'folke/flash.nvim',
        opts = {
            modes = { search = { enabled = true } },
        },
        config = function(_, opts)
            require('flash').setup(opts)
            map({ 'n', 'x', 'o' }, 's', function() require('flash').jump() end)
            map({ 'n', 'x', 'o' }, 'S', function() require('flash').treesitter() end)
            map('o', 'r', function() require('flash').remote() end)
            map({ 'o', 'x' }, 'R', function() require('flash').treesitter_search() end)
            map('c', '<c-s>', function() require('flash').toggle() end)
        end,
    },
    {
        'kylechui/nvim-surround',
        config = true,
    },
    {
        'kevinhwang91/nvim-ufo',
        dependencies = { 'kevinhwang91/promise-async' },
        opts = {
            provider_selector = function()
                return { 'treesitter', 'indent' }
            end,
        },
        config = function(_, opts)
            require('ufo').setup(opts)
            map('n', 'zR', require('ufo').openAllFolds)
            map('n', 'zM', require('ufo').closeAllFolds)
        end,
    },
    {
        enabled = false,
        'barrettruth/cp.nvim',
        dependencies = { 'ibhagwan/fzf-lua' },
        init = function()
            -- Keep uv cache in-project so cp.nvim scraping works in restricted environments.
            if vim.env.UV_CACHE_DIR == nil or vim.env.UV_CACHE_DIR == '' then
                local uv_cache_dir = vim.fn.getcwd() .. '/.uv-cache'
                vim.fn.mkdir(uv_cache_dir, 'p')
                vim.env.UV_CACHE_DIR = uv_cache_dir
            end

            vim.g.cp = {
                languages = {
                    python = {
                        extension = 'py',
                        commands = {
                            run = { 'python3', '{source}' },
                            debug = { 'python3', '{source}' },
                        },
                    },
                },
                platforms = {
                    codeforces = {
                        enabled_languages = { 'python' },
                        default_language = 'python',
                    },
                    atcoder = {
                        enabled_languages = { 'python' },
                        default_language = 'python',
                    },
                    cses = {
                        enabled_languages = { 'python' },
                        default_language = 'python',
                    },
                },
                open_url = true,
                ui = {
                    picker = 'fzf-lua',
                },
            }
        end,
        config = function()
            local function open_url(url)
                local ok_ui_open, opened = pcall(vim.ui.open, url)
                if ok_ui_open and opened ~= false then
                    return
                end

                local opener = nil
                if vim.fn.has('macunix') == 1 then
                    opener = 'open'
                elseif vim.fn.has('unix') == 1 then
                    opener = 'xdg-open'
                end

                if opener then
                    vim.fn.jobstart({ opener, url }, { detach = true })
                end
            end

            local function open_current_cp_problem_url()
                local ok_state, state = pcall(require, 'cp.state')
                local ok_cache, cache = pcall(require, 'cp.cache')
                if not (ok_state and ok_cache) then
                    return
                end

                local platform = state.get_platform()
                local contest_id = state.get_contest_id()
                local problem_id = state.get_problem_id()
                if not (platform and contest_id and problem_id) then
                    return
                end

                cache.load()
                local contest = cache.get_contest_data(platform, contest_id)
                if contest and contest.url then
                    open_url(contest.url:format(problem_id))
                end
            end

            -- cp.nvim only opens URLs when first entering a contest; extend this locally for next/prev.
            local ok_setup, setup = pcall(require, 'cp.setup')
            local ok_config, cp_config = pcall(require, 'cp.config')
            if ok_setup and ok_config and not setup._url_open_patch_applied then
                local original_navigate_problem = setup.navigate_problem
                setup.navigate_problem = function(direction, language)
                    local ok_state, state = pcall(require, 'cp.state')
                    local old_problem_id = ok_state and state.get_problem_id() or nil
                    original_navigate_problem(direction, language)

                    local cfg = cp_config.get_config()
                    local new_problem_id = ok_state and state.get_problem_id() or nil
                    local moved = old_problem_id ~= nil and new_problem_id ~= nil and old_problem_id ~= new_problem_id
                    if cfg and cfg.open_url and moved then
                        vim.schedule(open_current_cp_problem_url)
                    end
                end
                setup._url_open_patch_applied = true
            end

            map('n', '<leader>cr', '<cmd>CP run<cr>', { desc = 'CP run' })
            map('n', '<leader>cp', '<cmd>CP panel<cr>', { desc = 'CP panel' })
            map('n', '<leader>ce', '<cmd>CP edit<cr>', { desc = 'CP edit tests' })
            map('n', '<leader>cn', '<cmd>CP next<cr>', { desc = 'CP next problem' })
            map('n', '<leader>cN', '<cmd>CP prev<cr>', { desc = 'CP previous problem' })
            map('n', '<leader>cc', '<cmd>CP pick<cr>', { desc = 'CP contest picker' })
            map('n', '<leader>ci', '<cmd>CP interact<cr>', { desc = 'CP interact' })
            map('n', '<leader>co', open_current_cp_problem_url, { desc = 'CP open problem url' })
        end,
    },
{
  'barrettruth/pending.nvim',
  init = function()
    map('n', '<leader>p', '<cmd>Pending<cr><cmd>only<cr>')
  end,
},
{
  'barrettruth/preview.nvim',
  init = function()
    vim.g.preview = {
      typst = true,
      latex = true,
      github = {
        output = function(ctx)
          return '/tmp/' .. vim.fn.fnamemodify(ctx.file, ':t:r') .. '.html'
        end,
      },
      mermaid = true,
    }
  end,
},
}
