local M = {}

local state = {
    document = {},
    slide_number = 1,
    floats = {},
    fill_factor = 0.8,
    md_file = nil,
}

---Plugin setup function
---@param opts table Plugin options
M.setup = function(opts)
    opts = opts or {}
end

---Create a floating window
---@param opts table: Window configuration
---@return table: Table with buf and win ids
local function create_floating_window(opts, enter)
    opts = opts or {}
    enter = enter or false

    -- Create a buffer
    local buf = vim.api.nvim_create_buf(false, true)

    -- Define window configuration
    local win_config = opts

    -- Create the floating window
    local win = vim.api.nvim_open_win(buf, enter, win_config)

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

    local pres_height = math.floor(math.min(vim.o.columns, vim.o.lines) * factor)
    -- apply an arbitrary factor to get a square shape, because a row height is bigger than a column width
    local pres_width = math.floor(pres_height * 2.2)

    local pres_start_col = math.floor((vim.o.columns - pres_width - 0.1) / 2)
    local pres_start_row = math.floor((vim.o.lines - pres_height - 0.1) / 2)

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
            width = pres_width,
            height = pres_height,
            style = "minimal",
            border = "rounded",
            col = pres_start_col,
            row = pres_start_row,
            zindex = 2,
        },
        footer = {
            relative = "editor",
            width = #state.footer,
            height = 1,
            style = "minimal",
            col = math.floor(vim.o.columns / 2 - #state.footer / 2),
            row = pres_start_row + pres_height + 2, -- + 2 for border
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

---Set footer
local set_footer = function()
    state.footer = string.format(" %d / %d - %s", state.slide_number, #state.document.slides, state.md_file)
end

---Set slide to the presentation buffer
local set_slide = function(slide_number)
    if 1 <= slide_number and slide_number <= #state.document.slides then
        state.slide_number = slide_number
        vim.api.nvim_set_option_value("modifiable", true, { buf = state.floats.presentation.buf })
        vim.api.nvim_buf_set_lines(state.floats.presentation.buf, 0, -1, false, state.document.slides[slide_number])
        vim.api.nvim_set_option_value("modifiable", false, { buf = state.floats.presentation.buf })
        set_footer()

        -- The footer width changes when we jump from slide 9 to slide 10, from 99 to 100 etc.
        local updated_windows = create_window_config { factor = state.fill_factor }
        vim.api.nvim_win_set_config(state.floats.footer.win, updated_windows.footer)

        vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, { state.footer })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end
end

---Execute bash code
---@param codeblock table Lines of code to execute
---@return table: table with output lines
local codeblock_bash = function(codeblock)
    local tempfile = vim.fn.tempname() .. ".sh"
    vim.fn.writefile(codeblock, tempfile)

    local result = vim.system({ "bash", tempfile }, { text = true }):wait()
    if result.code ~= 0 then
        local output = vim.split(result.stderr, "\n")
        return output
    end

    local output = vim.split(result.stdout, "\n")
    return output
end

---Execute python code
---@param codeblock table Lines of code to execute
---@return table: table with output lines
local codeblock_python = function(codeblock)
    local tempfile = vim.fn.tempname() .. ".py"
    vim.fn.writefile(codeblock, tempfile)

    local result = vim.system({ "python", tempfile }, { text = true }):wait()
    if result.code ~= 0 then
        local output = vim.split(result.stderr, "\n")
        return output
    end

    local output = vim.split(result.stdout, "\n")
    return output
end

local options = {
    executors = {
        bash = codeblock_bash,
        python = codeblock_python,
    },
}

---Execute code block under cursor
local run_codeblock = function()
    local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
    local codeblock = {}
    local current_line = vim.api.nvim_get_current_line()
    if not current_line:find "^```" then
        print "Not on a code block!"
        return
    end
    local lines = vim.api.nvim_buf_get_lines(0, row, -1, false)
    local endrow = row
    for _, line in ipairs(lines) do
        endrow = endrow + 1
        if line:find "^```" then
            break
        end
        table.insert(codeblock, line)
    end

    local executor = string.gsub(current_line, "```", "")
    local output = options.executors[executor](codeblock)

    if output[#output] == "" then
        table.remove(output)
    end

    table.insert(output, 1, "```")
    table.insert(output, 1, "")
    table.insert(output, "```")

    vim.api.nvim_set_option_value("modifiable", true, { buf = state.floats.presentation.buf })
    vim.api.nvim_buf_set_lines(0, endrow, endrow, false, output)
    vim.api.nvim_set_option_value("modifiable", false, { buf = state.floats.presentation.buf })
end

---Start markdown presentation
M.mdp = function(opts)
    opts = opts or {}
    opts.bufnr = opts.bufnr or 0

    state.md_file = string.match(vim.api.nvim_buf_get_name(opts.bufnr), "[^/]+$")

    local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)

    state.document = parse_slides(lines)
    -- FIXME it is wierd that the footer is set two times for the first slide, but we need to know the footer length
    -- to place the footer window
    set_footer()
    local windows = create_window_config { factor = state.fill_factor }
    state.slide_number = 1
    state.floats.background = create_floating_window(windows.background)
    state.floats.footer = create_floating_window(windows.footer)
    state.floats.presentation = create_floating_window(windows.presentation, true)

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
            -- TODO for loop
            pcall(vim.api.nvim_win_close, state.floats.background.win, true)
            pcall(vim.api.nvim_win_close, state.floats.footer.win, true)
        end,
    })

    -- Define keymaps
    -- Next slide
    mdp_keymap("n", "n", function()
        set_slide(state.slide_number + 1)
    end)

    -- Previous slide
    mdp_keymap("n", "p", function()
        set_slide(state.slide_number - 1)
    end)

    -- First slide
    mdp_keymap("n", "gg", function()
        set_slide(1)
    end)

    -- Last slide
    mdp_keymap("n", "G", function()
        set_slide(#state.document.slides)
    end)

    -- Quit presentation
    mdp_keymap("n", "q", function()
        vim.api.nvim_win_close(state.floats.presentation.win, true)
    end)

    -- Decrease presentation floating window relative size
    mdp_keymap("n", "-", function()
        state.fill_factor = math.max(state.fill_factor - 0.1, 0.4)
        local updated_windows = create_window_config { factor = state.fill_factor }
        -- TODO for loop
        vim.api.nvim_win_set_config(state.floats.presentation.win, updated_windows.presentation)
        vim.api.nvim_win_set_config(state.floats.footer.win, updated_windows.footer)
    end)

    -- Increase presentation floating window relative size
    mdp_keymap("n", "+", function()
        state.fill_factor = math.min(state.fill_factor + 0.1, 1)
        local updated_windows = create_window_config { factor = state.fill_factor }
        -- TODO for loop
        vim.api.nvim_win_set_config(state.floats.presentation.win, updated_windows.presentation)
        vim.api.nvim_win_set_config(state.floats.footer.win, updated_windows.footer)
    end)

    -- Execute code block under cursor
    mdp_keymap("n", "x", run_codeblock)

    -- Next code block
    mdp_keymap("n", "X", function() vim.fn.search("^```\\w") end)

    -- Update windows properties on resize
    vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("mdp-resized", {}),
        callback = function()
            if vim.api.nvim_win_is_valid(state.floats.presentation.win) then
                local updated_windows = create_window_config { factor = state.fill_factor }
                for window, float in pairs(state.floats) do
                    vim.api.nvim_win_set_config(float.win, updated_windows[window])
                end
            end
        end,
    })

    -- Display first slide
    set_slide(1)
    -- vim.api.nvim_buf_set_lines(state.floats.presentation.buf, 0, -1, false, state.document.slides[1])

    -- Enter non-modifiable mode
    vim.api.nvim_set_option_value("modifiable", false, { buf = state.floats.presentation.buf })
end

-- FIXME to remove
-- if vim.api.nvim_buf_get_name(0):find "/mdp.nvim/lua/mdp.lua$" then
--     M.mdp { bufnr = 2 }
-- end

return M
