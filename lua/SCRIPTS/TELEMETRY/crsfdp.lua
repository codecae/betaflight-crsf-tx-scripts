
CRSF_FRAMETYPE_DISPLAYPORT_CMD      = 0x7D
CRSF_DISPLAYPORT_SUBCMD_UPDATE      = 0x01
CRSF_DISPLAYPORT_SUBCMD_CLEAR       = 0x02
CRSF_DISPLAYPORT_SUBCMD_OPEN        = 0x03
CRSF_DISPLAYPORT_SUBCMD_CLOSE       = 0x04
CRSF_DISPLAYPORT_SUBCMD_POLL        = 0x05
CRSF_DISPLAYPORT_SUBCMD_ACK         = 0x06
CRSF_ADDRESS_BETAFLIGHT             = 0xC8
CRSF_ADDRESS_TRANSMITTER            = 0xEA

cmsMenuOpen = false
lastMenuEventTime = 0
ackRow = -1
radio = {}

local supportedPlatforms = {
    x7 =
    {
        refresh = {
            event = EVT_ENTER_BREAK,
            text = "Refresh: [ENT]",
            top = 1,
            left = 64,
        },
        lcd = {
            width = 128,
            height = 64,
            rows = 8,
            cols = 26,
            pixelsPerRow = 8,
            pixelsPerChar = 5,
        }
    },
    x9 =
    {
        refresh = {
            event = EVT_PLUS_BREAK,
            text = "Refresh: [+]",
            top = 1,
            left = 156,
        },
        lcd = {
            width = 212,
            height = 64,
            rows = 8,
            cols = 32,
            topPadding = 2,
            pixelsPerRow = 8,
            pixelsPerChar = 6,
        }
    },
}

local supportedRadios =
{
    ["x7"] = supportedPlatforms.x7,
    ["x7s"] = supportedPlatforms.x7,
    ["x9d"] = supportedPlatforms.x9,
    ["x9d+"] = supportedPlatforms.x9,
}

screenBuffer = {
    rows = 8,
    cols = 32,
    buffer = {},
    resetRow = function(row)
        screenBuffer.buffer[row] = string.rep(" ", screenBuffer.cols)
    end,
    reset = function()
        for i=1, screenBuffer.rows do
            screenBuffer.resetRow(i)
        end
    end,
    update = function(row,col,str) 
        if row > screenBuffer.rows or col > screenBuffer.cols then
            return nil
        end
        local bufferLeft = string.sub(screenBuffer.buffer[row],1,col-1)
        local bufferRightStart = string.len(bufferLeft) + string.len(str) + 1
        local bufferRight = string.sub(screenBuffer.buffer[row],bufferRightStart, screenBuffer.cols)
        screenBuffer.buffer[row] = string.sub(string.format("%s%s%s", bufferLeft, str, bufferRight),1,screenBuffer.cols)
    end,
    draw = function()
        lcd.clear()
        -- draw buffer monospaced, as font characters vary in width.
        for row=1,screenBuffer.rows do
            for col=1,screenBuffer.cols do
                char = string.sub(screenBuffer.buffer[row], col, col)
                xPos = ((col-1)*radio.lcd.pixelsPerChar)+1
                yPos = ((row-1)*radio.lcd.pixelsPerRow)+1
                lcd.drawText(xPos, yPos, char, SMLSIZE) 
            end
        end
        lcd.drawText(radio.refresh.left, radio.refresh.top, radio.refresh.text, SMLSIZE) 
    end
}

local function subrange(t, first, last)
    local sub = {}
    for i=first,last do
        sub[#sub + 1] = t[i]
    end
    return sub
end

local function arrayToString(arr)
    local str = ""
    for i=1,#arr do
        str = string.format("%s%c",str,arr[i])
    end
    return str
end

local function displayPortCmd(cmd, data)
    local payloadOut = { CRSF_ADDRESS_BETAFLIGHT, CRSF_ADDRESS_TRANSMITTER, cmd }
    if data ~= nil then
        for i=1,#(data) do
            payloadOut[3+i] = data[i]
        end
    end
    crossfireTelemetryPush(CRSF_FRAMETYPE_DISPLAYPORT_CMD, payloadOut) 
end

local function init()
    local ver, rad, maj, min, rev = getVersion()
    radio = supportedRadios[rad]
    if not radio then
        error("Radio not supported: "..rad)
    end
    screenBuffer.rows = radio.lcd.rows
    screenBuffer.cols = radio.lcd.cols
    screenBuffer.reset()
end

local function run(event)
    lastMenuEventTime = getTime()
    local command, data = crossfireTelemetryPop()
    if (data ~= nil) and (#data > 2) then
        if (command == CRSF_FRAMETYPE_DISPLAYPORT_CMD) and (data[1] == CRSF_ADDRESS_TRANSMITTER) and (data[2] == CRSF_ADDRESS_BETAFLIGHT) then
            local subCommand = data[3];
            if (subCommand == CRSF_DISPLAYPORT_SUBCMD_UPDATE) then
                local row = data[4] 
                ackRow = row
                screenBuffer.update(row+1,1,arrayToString(subrange(data,5,#data-1)))
                cmsMenuOpen = true
            elseif (subCommand == CRSF_DISPLAYPORT_SUBCMD_CLEAR) then
                screenBuffer.reset()
            end
        end
    end
    screenBuffer.draw()
    if cmsMenuOpen == false then
        displayPortCmd(CRSF_DISPLAYPORT_SUBCMD_OPEN, { screenBuffer.rows, screenBuffer.cols })
    end
    if ackRow >= 0 {
        displayPortCmd(CRSF_DISPLAYPORT_SUBCMD_ACK, { ackRow })
        ackRow = -1
    }
    if (event == radio.refresh.event) then
        displayPortCmd(CRSF_DISPLAYPORT_SUBCMD_POLL, nil)
    end
end

local function background()
    if cmsMenuOpen == true and lastMenuEventTime + 100 < getTime() then
        displayPortCmd(CRSF_DISPLAYPORT_SUBCMD_CLOSE, nil)
        cmsMenuOpen = false
    end
end

return { init=init, run=run, background=background }