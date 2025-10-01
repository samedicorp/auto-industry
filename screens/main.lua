local Module = {
    status = {},
    detail = {},
    skipOk = true,
}

function Module:render(payload, toolkit)
    local status = self.status
    local detail = self.detail
    local reply

    if payload then
        if payload.command == "status" then
            local key = payload.status.key
            status[key] = payload.status.value
            detail[key] = payload.status.detail
        end
        reply = { name = payload.command, result = "ok" }
    end

    local screen = toolkit.Screen.new()
    local layer = screen:addLayer()

    local cOK = toolkit.Color.new(0, 1, 0)
    local cRunning = toolkit.Color.new(1, 1, 0)
    local cWarn = toolkit.Color.new(1, 0, 0)
    local cDetail = toolkit.Color.new(0.39, 0.39, 0.39)
    local fMain = toolkit.Font.new("Play", 14)
    local fDetail = toolkit.Font.new("Play", 9)
    local lineHeight = 22
    local detailOffset = 6
    local detailOptions = { font = fDetail, fill = cDetail, align = { h = toolkit.alignLeft, v = toolkit.alignBottom } }
    local valueOptions = { font = fMain, align = { h = toolkit.alignLeft, v = toolkit.alignBottom } }

    local gotItems = false

    local y = 50
    for n, line in pairs(status) do
        local color
        local skip = false
        if string.find(line, "Running") then
            color = cRunning
        elseif string.find(line, "OK") then
            color = cOK
            skip = self.skipOk
        else
            color = cWarn
        end

        if not skip then
            local labelOptions = { font = fMain, fill = color, align = { h = toolkit.alignLeft, v = toolkit.alignBottom } }
            local label = layer:addLabel({ 10, y, 300, lineHeight - detailOffset }, n, labelOptions)
            local value = layer:addLabel({ 300, y, 300, lineHeight - detailOffset }, line, valueOptions)
            local detail = layer:addLabel({ 302, y, 300, lineHeight }, detail[n] or "", detailOptions)
            y = y + lineHeight
            gotItems = true
        end
    end

    local label
    if self.skipOk then
        label = "show ok"
    else
        label = "hide ok"
    end

    layer:addButton({ 900, 0, 100, 30 }, label, {
        style = "line",
        onMouseUp = function()
            debugf("toggling skipOk from %s", tostring(self.skipOk))
            self.skipOk = not self.skipOk
        end
    })

    if not gotItems then
        local label = layer:addLabel({ 0, 0, 300, 40 }, "Starting Industry...")
    end

    layer:render()
    screen:scheduleRefresh()

    return reply
end

return Module
