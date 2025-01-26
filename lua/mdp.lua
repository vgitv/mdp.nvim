local M = {}

local state = {
    document = {},
    slide_number = 1,
    floats = {},
    fill_factor = 0.8,
}

---Plugin setup function
---@param opts table Plugin options
M.setup = function(opts)
    opts = opts or {}
    vim.api.nvim_create_user_command("Mdp", function()
        M.mdp { bufnr = 0 }
    end, {
        desc = "Start markdown presentation from current buffer",
    })
end

---Create a floating window
---@param opts table: Window configuration
---@return table: Table with buf and win ids
local function create_floating_window(opts)
    opts = opts or {}

    -- Create a buffer
    local buf = vim.api.nvim_create_buf(false, true)

    -- Define window configuration
    local win_config = opts

    -- Create the floating window
    local win = vim.api.nvim_open_win(buf, true, win_config)

    return { buf = buf, win = win }
end

---Create buffer-local keymap
local mdp_keymap = function(mode, key, callback)
    vim.keymap.set(mode, key, callback, { buffer = state.floats.presentation.buf })
end

---Generate windows configurations
---@return table: Table of multiple windows configurations
local create_window_config = function(opts)
    opts = opts or {}
    local factor = opts.factor or 0.8

    local presentation_height = math.floor(vim.o.lines * factor)
    local presentation_width = math.floor(vim.o.columns * factor)

    return {
        background = {
            relative = "editor",
            width = vim.o.columns,
            height = vim.o.lines,
            style = "minimal",
            col = 0,
            row = 0,
            zindex = 1,
        },
        presentation = {
            relative = "editor",
            width = presentation_width,
            height = presentation_height,
            style = "minimal",
            border = "rounded",
            row = math.floor((vim.o.lines - presentation_height - 0.1) / 2),
            col = math.floor((vim.o.columns - presentation_width - 0.1) / 2),
            zindex = 2,
        },
    }
end

---Takes lines and parses them into slides
---@param lines string[]: The lines in the buffer
---@return table: Table with slides
local parse_slides = function(lines)
    local document = { slides = {} }
    local slide = {}

    local separator = "^---"

    for _, line in ipairs(lines) do
        if line:find(separator) then
            if #slide > 0 then
                table.insert(document.slides, slide)
                slide = {}
            end
        else
            if not (#slide == 0 and line == "") then
                -- dont insert blank line at the slide begining
                table.insert(slide, line)
            end
        end
    end

    table.insert(document.slides, slide)

    return document
end

---Start markdown presentation
M.mdp = function(opts)
    opts = opts or {}
    opts.bufnr = opts.bufnr or 0

    local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
    local windows = create_window_config({ factor = state.fill_factor })

    state.document = parse_slides(lines)
    state.slide_number = 1
    state.floats.background = create_floating_window(windows.background)
    state.floats.presentation = create_floating_window(windows.presentation)

    -- Set local options
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = state.floats.presentation.buf })
    vim.api.nvim_set_option_value("colorcolumn", "", { win = state.floats.presentation.win })

    -- Define global options
    local plugin_options = {
        cmdheight = {
            original = vim.o.cmdheight,
            plugin = 0,
        },
        mouse = {
            original = vim.o.mouse,
            plugin = "",
        },
    }

    -- Set global options
    for option, config in pairs(plugin_options) do
        vim.opt[option] = config.plugin
    end

    -- Restore global options
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = state.floats.presentation.buf,
        callback = function()
            for option, config in pairs(plugin_options) do
                vim.opt[option] = config.original
            end
            vim.api.nvim_win_close(state.floats.background.win, true)
        end,
    })

    -- Define keymaps
    -- Next slide
    mdp_keymap("n", "n", function()
        if state.slide_number < #state.document.slides then
            state.slide_number = state.slide_number + 1
            vim.api.nvim_set_option_value("modifiable", true, { buf = state.floats.presentation.buf })
            vim.api.nvim_buf_set_lines(state.floats.presentation.buf, 0, -1, false, state.document.slides[state.slide_number])
            vim.api.nvim_set_option_value("modifiable", false, { buf = state.floats.presentation.buf })
        end
        vim.cmd "normal gg0"
    end)

    -- Previous slide
    mdp_keymap("n", "p", function()
        if state.slide_number > 1 then
            state.slide_number = state.slide_number - 1
            vim.api.nvim_set_option_value("modifiable", true, { buf = state.floats.presentation.buf })
            vim.api.nvim_buf_set_lines(state.floats.presentation.buf, 0, -1, false, state.document.slides[state.slide_number])
            vim.api.nvim_set_option_value("modifiable", false, { buf = state.floats.presentation.buf })
        end
        vim.cmd "normal gg0"
    end)

    -- Quit presentation
    mdp_keymap("n", "q", function()
        vim.api.nvim_win_close(state.floats.presentation.win, true)
    end)

    -- Decrease presentation floating window relative size
    mdp_keymap("n", "-", function()
        state.fill_factor = math.max(state.fill_factor - 0.1, 0.5)
        local updated_windows = create_window_config({ factor = state.fill_factor })
        vim.api.nvim_win_set_config(state.floats.presentation.win, updated_windows.presentation)
    end)

    -- Increase presentation floating window relative size
    mdp_keymap("n", "+", function()
        state.fill_factor = math.min(state.fill_factor + 0.1, 0.9)
        local updated_windows = create_window_config({ factor = state.fill_factor })
        vim.api.nvim_win_set_config(state.floats.presentation.win, updated_windows.presentation)
    end)

    -- Update windows properties on resize
    vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("mdp-resized", {}),
        callback = function()
            if vim.api.nvim_win_is_valid(state.floats.presentation.win) then
                local updated_windows = create_window_config({ factor = state.fill_factor })
                for window, float in pairs(state.floats) do
                    vim.api.nvim_win_set_config(float.win, updated_windows[window])
                end
            end
        end
    })

    -- Display first slide
    vim.api.nvim_buf_set_lines(state.floats.presentation.buf, 0, -1, false, state.document.slides[1])

    -- Enter non-modifiable mode
    vim.api.nvim_set_option_value("modifiable", false, { buf = state.floats.presentation.buf })
end

-- FIXME to remove
if vim.api.nvim_buf_get_name(0):find "/mdp.nvim/lua/mdp.lua$" then
    M.mdp { bufnr = 2 }
end

return M
