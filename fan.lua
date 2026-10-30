local monitor = peripheral.find("monitor")

monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()

local w, h = monitor.getSize()

local cx = (w + 1) / 2
local cy = (h + 1) / 2

local radius = 12
local xScale = 1.3

local bladeLength = radius - 2
local bladeStart = 1.5
local bladeWidth = 3.5
local rotation = 0

while true do
    monitor.clear()

    -- Outer circle
    for angle = 0, 359 do
        local r = math.rad(angle)

        local x = math.floor(cx + math.cos(r) * radius * xScale + 0.5)
        local y = math.floor(cy + math.sin(r) * radius + 0.5)

        if x >= 1 and x <= w and y >= 1 and y <= h then
            monitor.setCursorPos(x, y)
            monitor.write("#")
        end
    end

    -- Blades
    for y = 1, h do
        for x = 1, w do

            local dx = (x - cx) / xScale
            local dy = y - cy

            local distance = math.sqrt(dx * dx + dy * dy)

            if distance >= bladeStart and distance <= bladeLength then

                local angle = math.atan2(dy, dx)

                for blade = 0, 3 do
                    local bladeAngle = rotation + blade * math.pi / 2

                    local difference = math.atan2(
                        math.sin(angle - bladeAngle),
                        math.cos(angle - bladeAngle)
                    )

                    if math.abs(difference) <= math.rad(bladeWidth * 3) then
                        monitor.setCursorPos(x, y)
                        monitor.write("#")
                        break
                    end
                end
            end
        end
    end

    rotation = rotation + math.rad(8)

    sleep(0.05)
end
