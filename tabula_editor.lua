-- SETTINGS
local CFG = {
    -- UI library file
    UI_LIB           = "ui_lib.lua",

    -- Program
    TITLE            = "TABULA EDITOR",
    DB_FILE          = "tabula_db",

    -- Table limits
    MAX_CELL_LEN     = 16,     -- max characters in a cell
    MAX_ROWS_VISIBLE = 10,
    MAX_SIZE         = 99,     -- max rows / columns
    ROW_NUM_W        = 5,      -- space reserved for row numbers (" 12  ")

    -- Status message
    STATUS_TIMEOUT   = 2,      -- seconds before status text disappears
}

-- UI
local ui = dofile(CFG.UI_LIB)

-- Runtime state
local data = { {""} }      -- minimum 1x1
local cursor_r, cursor_c = 1, 1
local scroll_r, scroll_c = 1, 1
local mode = "nav"         -- "nav" | "edit"
local edit_buf = ""
local status = ""
local status_timer = nil

local function setStatus(msg)
    status = msg
    if status_timer then
        os.cancelTimer(status_timer)
    end
    status_timer = os.startTimer(CFG.STATUS_TIMEOUT)
end

-- Data helpers
local function ensure(r, c)
    r = math.min(r, CFG.MAX_SIZE)
    c = math.min(c, CFG.MAX_SIZE)
    while #data < r do
        local row = {}
        for i = 1, math.max(#data[1] or 1, c) do
            row[i] = ""
        end
        table.insert(data, row)
    end
    for _, row in ipairs(data) do
        while #row < c do
            table.insert(row, "")
        end
    end
end

local function trim()
    -- remove empty rows from the bottom
    while #data > 1 do
        local empty = true
        for _, v in ipairs(data[#data]) do
            if v ~= "" then empty = false break end
        end
        if empty then table.remove(data) else break end
    end
    -- remove empty columns from the right
    if #data == 0 then data = {{""}} return end
    local cols = #data[1]
    while cols > 1 do
        local empty = true
        for _, row in ipairs(data) do
            if row[cols] and row[cols] ~= "" then empty = false break end
        end
        if empty then
            for _, row in ipairs(data) do table.remove(row, cols) end
            cols = cols - 1
        else
            break
        end
    end
end

local function clampCursor()
    local maxR = math.max(1, #data)
    local maxC = math.max(1, #data[1] or 1)
    cursor_r = math.max(1, math.min(cursor_r, maxR))
    cursor_c = math.max(1, math.min(cursor_c, maxC))
    if cursor_r < scroll_r then scroll_r = cursor_r end
    if cursor_c < scroll_c then scroll_c = cursor_c end
end

local function save()
    trim()
    clampCursor()
    local ok = pcall(function()
        local h = fs.open(CFG.DB_FILE, "w")
        h.write(textutils.serialize(data))
        h.close()
    end)
    setStatus(ok and "Saved" or "Save error")
end

local function load()
    if not fs.exists(CFG.DB_FILE) then return end
    local ok, loaded = pcall(function()
        local h = fs.open(CFG.DB_FILE, "r")
        local raw = h.readAll()
        h.close()
        return textutils.unserialize(raw)
    end)
    if ok and type(loaded) == "table" and #loaded > 0 then
        data = loaded
        -- normalize column count
        local maxc = 0
        for _, row in ipairs(data) do maxc = math.max(maxc, #row) end
        for _, row in ipairs(data) do
            while #row < maxc do table.insert(row, "") end
        end
    end
end


-- Drawing

-- Per-column width: each column sized by its own longest cell.
-- Always reserves 2 chars for [ ] so selection doesn't shift neighbors.
local function calcColWidths()
    local cols = #data[1] or 1
    local widths = {}
    for c = 1, cols do
        local maxLen = 1
        for _, row in ipairs(data) do
            local len = #tostring(row[c] or "")
            if len > maxLen then maxLen = len end
        end
        if mode == "edit" and c == cursor_c then
            local len = #edit_buf
            if len > maxLen then maxLen = len end
        end
        maxLen = math.min(maxLen, CFG.MAX_CELL_LEN)
        widths[c] = math.max(5, maxLen + 2)  -- +2 for [ ]
    end
    return widths
end

-- How many columns fit starting from scroll_c given available width
local function fitColumns(widths, startCol, avail)
    local used = 0
    local count = 0
    local totalCols = #widths
    for c = startCol, totalCols do
        local w = widths[c] or 5
        if used + w > avail and count > 0 then break end
        used = used + w
        count = count + 1
    end
    return math.max(1, count)
end

local function draw()
    ui.clearContent()
    ui.title(CFG.TITLE)

    local widths = calcColWidths()
    local avail = ui.WIDTH - CFG.ROW_NUM_W
    local colsVisible = fitColumns(widths, scroll_c, avail)

    -- keep cursor column in view
    if cursor_c < scroll_c then
        scroll_c = cursor_c
        colsVisible = fitColumns(widths, scroll_c, avail)
    end
    while cursor_c >= scroll_c + colsVisible do
        scroll_c = scroll_c + 1
        colsVisible = fitColumns(widths, scroll_c, avail)
    end

    -- info line
    ui.setRow(4, string.format("  Size: %dx%d   Cursor: [%d,%d]   %s",
        #data, #data[1] or 0, cursor_r, cursor_c, status), ui.GRAY)

    -- column headers
    local header = string.rep(" ", CFG.ROW_NUM_W)
    for c = scroll_c, scroll_c + colsVisible - 1 do
        if c > (#data[1] or 1) then break end
        local w = widths[c] or 5
        header = header .. string.format("%-" .. w .. "s", tostring(c))
    end
    ui.setRow(5, header, ui.ORANGE)

    -- data rows
    local rowY = 6
    for r = scroll_r, math.min(scroll_r + CFG.MAX_ROWS_VISIBLE - 1, #data) do
        local line = string.format("%3d  ", r)
        for c = scroll_c, scroll_c + colsVisible - 1 do
            if c > (#data[1] or 1) then break end
            local w = widths[c] or 5
            local cell = data[r][c] or ""
            local text

            if mode == "edit" and r == cursor_r and c == cursor_c then
                text = (edit_buf .. "_"):sub(1, w)
            elseif r == cursor_r and c == cursor_c then
                local inner = (cell ~= "" and cell or " "):sub(1, w - 2)
                text = "[" .. inner .. "]"
            else
                text = cell:sub(1, w)
            end

            while #text < w do text = text .. " " end
            text = text:sub(1, w)
            line = line .. text
        end
        local color = (r == cursor_r) and ui.ORANGE or ui.WHITE
        ui.setRow(rowY, line, color)
        rowY = rowY + 1
    end

    -- help line
    if mode == "edit" then
        ui.setRow(17, "  EDIT MODE: Start typing text | Enter = save", ui.ORANGE)
    else
        ui.setRow(17, "  Arrows = move | Enter = edit | S = save", ui.GRAY)
    end
end

-- Navigation
local function move(dr, dc)
    cursor_r = math.max(1, math.min(CFG.MAX_SIZE, cursor_r + dr))
    cursor_c = math.max(1, math.min(CFG.MAX_SIZE, cursor_c + dc))
    ensure(cursor_r, cursor_c)

    -- auto-scroll rows (columns handled in draw)
    if cursor_r < scroll_r then scroll_r = cursor_r end
    if cursor_r >= scroll_r + CFG.MAX_ROWS_VISIBLE then
        scroll_r = cursor_r - CFG.MAX_ROWS_VISIBLE + 1
    end
    if cursor_c < scroll_c then scroll_c = cursor_c end
end

-- Main loop
load()
draw()

while true do
    local event, p1 = os.pullEvent()

    if event == "timer" and p1 == status_timer then
        status = ""
        status_timer = nil
        draw()

    elseif event == "key" then
        local key = p1

        if mode == "nav" then
            if key == keys.up then
                move(-1, 0)
            elseif key == keys.down then
                move(1, 0)
            elseif key == keys.left then
                move(0, -1)
            elseif key == keys.right then
                move(0, 1)
            elseif key == keys.enter then
                clampCursor()
                mode = "edit"
                local row = data[cursor_r] or {""}
                edit_buf = (row[cursor_c] or ""):sub(1, CFG.MAX_CELL_LEN)
                status = ""
            elseif key == keys.s then
                save()
            else
                status = ""
            end
            draw()

        elseif mode == "edit" then
            if key == keys.enter then
                ensure(cursor_r, cursor_c)
                data[cursor_r][cursor_c] = edit_buf:sub(1, CFG.MAX_CELL_LEN)
                mode = "nav"
                setStatus("Written")
                draw()
            elseif key == keys.backspace then
                edit_buf = edit_buf:sub(1, -2)
                draw()
            end
        end

    elseif event == "char" and mode == "edit" then
        if #edit_buf < CFG.MAX_CELL_LEN then
            edit_buf = edit_buf .. p1
            draw()
        end
    end
end
