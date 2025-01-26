local M = {}

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

---Generate windows configurations
---@return table: Table of multiple windows configurations
local create_window_config = function()
    local presentation_height = math.floor(vim.o.lines * 0.8)
    local presentation_width = math.floor(vim.o.columns * 0.8)

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

---Takes lines and parse them into slides
---@param lines string[]: The lines in the buffer
---@return table: Table with slides
local parse_slides = function(lines)
    local document = { slides = {} }
    local current_slide = {}

    local separator = "^---"

    for _, line in ipairs(lines) do
        if line:find(separator) then
            if #current_slide > 0 then
                table.insert(document.slides, current_slide)
                current_slide = {}
            end
        else
            if not (#current_slide == 0 and line == "") then
                -- dont insert blank line at the slide begining
                table.insert(current_slide, line)
            end
        end
    end

    table.insert(document.slides, current_slide)

    return document
end

---Start markdown presentation
M.mdp = function(opts)
    opts = opts or {}
    opts.bufnr = opts.bufnr or 0
    local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
    local document = parse_slides(lines)
    local current_slide = 1

    local windows = create_window_config()
    local background_float = create_floating_window(windows.background)
    local presentation_float = create_floating_window(windows.presentation)

    -- Set local options
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = presentation_float.buf })
    vim.api.nvim_set_option_value("colorcolumn", "", { win = presentation_float.win })

    -- Set global option
    local plugin_options = {
        cmdheight = {
            original = vim.o.cmdheight,
            plugin = 0,
        },
        mouse = {
            original = vim.o.mouse,
            plugin = "",
        }
    }

    for option, config in pairs(plugin_options) do
        vim.opt[option] = config.plugin
    end

    -- Restore global options
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = presentation_float.buf,
        callback = function()
            for option, config in pairs(plugin_options) do
                vim.opt[option] = config.original
            end
            vim.api.nvim_win_close(background_float.win, true)
        end,
    })

    -- Define keymaps
    vim.keymap.set("n", "n", function()
        if current_slide < #document.slides then
            current_slide = current_slide + 1
            vim.api.nvim_set_option_value("modifiable", true, { buf = presentation_float.buf })
            vim.api.nvim_buf_set_lines(presentation_float.buf, 0, -1, false, document.slides[current_slide])
            vim.api.nvim_set_option_value("modifiable", false, { buf = presentation_float.buf })
        end
    end, { buffer = presentation_float.buf })

    vim.keymap.set("n", "p", function()
        if current_slide > 1 then
            current_slide = current_slide - 1
            vim.api.nvim_set_option_value("modifiable", true, { buf = presentation_float.buf })
            vim.api.nvim_buf_set_lines(presentation_float.buf, 0, -1, false, document.slides[current_slide])
            vim.api.nvim_set_option_value("modifiable", false, { buf = presentation_float.buf })
        end
    end, { buffer = presentation_float.buf })

    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(presentation_float.win, true)
    end, { buffer = presentation_float.buf })

    -- Update windows properties on resize
    vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("mdp-resized", {}),
        callback = function()
            if vim.api.nvim_win_is_valid(presentation_float.win) then
                local updated_windows = create_window_config()
                vim.api.nvim_win_set_config(background_float.win, updated_windows.background)
                vim.api.nvim_win_set_config(presentation_float.win, updated_windows.presentation)
            end
        end
    })

    -- Display first slide
    vim.api.nvim_buf_set_lines(presentation_float.buf, 0, -1, false, document.slides[1])

    -- Enter non-modifiable mode
    vim.api.nvim_set_option_value("modifiable", false, { buf = presentation_float.buf })
end

-- FIXME to remove
if vim.api.nvim_buf_get_name(0):find "/mdp.nvim/lua/mdp.lua$" then
    M.mdp { bufnr = 2 }
end

return M
