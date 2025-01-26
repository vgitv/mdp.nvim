local M = {}

M.setup = function()
    vim.api.nvim_create_user_command("Mdp", function()
        M.start_presentation { bufnr = 0 }
    end, {
        desc = "Markdown presentation",
    })
end

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

---@class present.Slides
---@fields slides string[]: The slides of the file

---Takes some lines and parses them
---@param lines string[]: The lines in the buffer
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

M.start_presentation = function(opts)
    opts = opts or {}
    opts.bufnr = opts.bufnr or 0
    local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
    local document = parse_slides(lines)
    local current_slide = 1

    local windows = create_window_config()
    local background_float = create_floating_window(windows.background)
    local presentation_float = create_floating_window(windows.presentation)

    vim.api.nvim_set_option_value("filetype", "markdown", { buf = presentation_float.buf })


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

    -- global options to restore
    for option, config in pairs(plugin_options) do
        vim.opt[option] = config.plugin
    end

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = presentation_float.buf,
        callback = function()
            for option, config in pairs(plugin_options) do
                vim.opt[option] = config.original
            end
            vim.api.nvim_win_close(background_float.win, true)
        end,
    })

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

    vim.api.nvim_buf_set_lines(presentation_float.buf, 0, -1, false, document.slides[1])
    vim.api.nvim_set_option_value("modifiable", false, { buf = presentation_float.buf })
end

if vim.api.nvim_buf_get_name(0):find "/mdp.nvim/lua/mdp.lua$" then
    M.start_presentation { bufnr = 6 }
end

return M
