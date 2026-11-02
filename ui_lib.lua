-- UI Library
-- Terminal size: 51 columns x 19 rows (default ComputerCraft size)
-- Row 1 and row 19 are reserved for the frame

local system = {}

-- Constants
system.WIDTH  = 51
system.HEIGHT = 19

system.ORANGE = colors.orange
system.WHITE  = colors.white
system.BLACK  = colors.black
system.GREEN  = colors.lime
system.RED    = colors.red
system.GRAY   = colors.gray

-- Custom orange palette
local function applyPalette()
    term.setPaletteColor(colors.orange, 1.0, 0.42, 0.08)
end

-- Content area
local ROWS = {
    [1]  = "/// neepOS v1.0 ///////////////////////////////////",
    [2]  = "                                                   ",
    [3]  = "                                                   ",
    [4]  = "                                                   ",
    [5]  = "                                                   ",
    [6]  = "                                                   ",
    [7]  = "                                                   ",
    [8]  = "                                                   ",
    [9]  = "                                                   ",
    [10] = "                                                   ",
    [11] = "                                                   ",
    [12] = "                                                   ",
    [13] = "                                                   ",
    [14] = "                                                   ",
    [15] = "                                                   ",
    [16] = "                                                   ",
    [17] = "                                                   ",
    [18] = "                                                   ",
    [19] = "/// (C) 1987-1994 /////////////////////////////////",
}

-- Core functions:

-- 1. Draw the entire screen from ROWS table
function system.draw()
    applyPalette()
    term.setBackgroundColor(system.BLACK)
    term.clear()

    for y = 1, system.HEIGHT do
        term.setCursorPos(1, y)
        if y == 1 or y == system.HEIGHT then
            term.setTextColor(system.ORANGE)
        else
            term.setTextColor(system.WHITE)
        end
        term.write(ROWS[y])
    end
end

-- 2. Set content of a specific row (2..18 only) text will be padded / truncated to 51 characters
function system.setRow(y, text, color)
    if y < 2 or y > (system.HEIGHT - 1) then return end

    text = tostring(text or "")
    if #text > system.WIDTH then
        text = text:sub(1, system.WIDTH)
    else
        text = text .. string.rep(" ", system.WIDTH - #text)
    end

    ROWS[y] = text

    -- Immediately draw this row
    term.setCursorPos(1, y)
    term.setTextColor(color or system.WHITE)
    term.write(ROWS[y])
end

-- 3. Write text at specific column inside a row
function system.write(x, y, text, color)
    if y < 2 or y > (system.HEIGHT - 1) then return end

    text = tostring(text or "")
    local row = ROWS[y]

    -- Replace part of the row
    local before = row:sub(1, x - 1)
    local after  = row:sub(x + #text)
    local newRow = before .. text .. after

    if #newRow > system.WIDTH then
        newRow = newRow:sub(1, system.WIDTH)
    elseif #newRow < system.WIDTH then
        newRow = newRow .. string.rep(" ", system.WIDTH - #newRow)
    end

    ROWS[y] = newRow

    term.setCursorPos(1, y)
    term.setTextColor(color or system.WHITE)
    term.write(ROWS[y])
end

-- 4. Clear one content row
function system.clearRow(y)
    system.setRow(y, "", system.WHITE)
end

-- 5. Clear all content rows (2..18)
function system.clearContent()
    for y = 2, system.HEIGHT - 1 do
        ROWS[y] = string.rep(" ", system.WIDTH)
    end
    system.draw()
end

-- Helpers
function system.title(text)
    system.setRow(3, "  " .. text, system.ORANGE)
end

function system.label(y, text)
    system.setRow(y, "  " .. text, system.WHITE)
end

function system.value(y, text, color)
    system.setRow(y, "  " .. text, color or system.WHITE)
end

function system.prompt(y)
    system.setRow(y,     "  Enter command:", system.WHITE)
    system.setRow(y + 1, "  > ",             system.ORANGE)
end

function system.commands(y, text)
    system.setRow(y, "  Possible commands: " .. text, system.GRAY)
end

function system.progressBar(y, width, percent)
    percent = math.max(0, math.min(100, percent or 0))
    local filled = math.floor((percent / 100) * width)
    local bar = "[" .. string.rep("#", filled) .. string.rep("-", width - filled) .. "] " .. math.floor(percent) .. "%"
    system.setRow(y, "  " .. bar, system.WHITE)
end

function system.center(y, text, color)
    text = tostring(text or "")
    local pad = math.floor((system.WIDTH - #text) / 2)
    system.setRow(y, string.rep(" ", pad) .. text, color or system.WHITE)
end

return system
