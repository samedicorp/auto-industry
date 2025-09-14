-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
--  Created by Samedi on 27/08/2022.
--  All code (c) 2022, The Samedi Corporation.
-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

-- If setting up manually, add the following handler to any connected screens:
-- local failure = modula:call("onScreenReply", output)
-- if failure then
--     error(failure)
-- end

local Module = {}

function Module:register(parameters)
    modula:registerForEvents(self, "onStart", "onStopping", "onCheckMachines", "onCommand")
    self.orderName = parameters.orderName or "samedicorp.auto-industry.default-order"
end

-- ---------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------

function Module:onStart()
    debugf("Auto Industry started.")

    self:attachToScreen()
    local industry = modula:getService("industry")
    self.industry = industry

    -- Dual Universe item IDs
    -- see http://du-lua.dev/#/items for reference

    -- local smelter = {
    --     ["511774178"] = 500,  -- Steel
    --     ["018262914"] = 500,  -- Al-Fe
    --     ["2565702107"] = 500, -- Silumin
    --     ["1034957327"] = 500, -- Calcium Reinforced Copper
    -- }

    -- local metalwork = {
    --     ["2660328728"] = 25,  -- Basic Burner
    --     ["1799107246"] = 100, -- Basic Pipe
    --     ["3936127019"] = 100, -- Basic Screw
    --     ["3936127018"] = 100, -- Uncommon Screw
    --     ["2662317132"] = 10,  -- Basic Combustion Chamber
    --     ["1981362643"] = 10,  -- Basic Standard Frame S
    --     ["994058182"] = 10,   -- Basic Reinforced Frame S
    --     ["1331181119"] = 100, -- Basic Hydraulics
    --     ["1981362536"] = 10,  -- Uncommon Standard Frame M
    --     ["994058204"] = 10,   -- Basic Reinforced Frame M
    --     ["625289720"] = 10,   -- Basic Chemical Container S
    -- }

    -- local printer = {
    --     ["1971447072"] = 10, -- Basic Injector
    --     ["466630565"] = 100, -- Basic Fixation
    -- }

    -- local chemical = {
    --     ["2014531313"] = 500, -- Polycarbonate
    --     ["840202984"] = 1000, -- Kergon X5
    -- }

    -- local glass = {
    --     ["3308209457"] = 100, -- Glass Product
    --     ["1942154251"] = 100, -- Advanced Glass Product
    --     ["1234754162"] = 100, -- Basic LED
    --     ["1234754161"] = 100, -- Uncommon LED
    -- }

    -- local electronics = {
    --     ["794666749"] = 100, -- Basic Component
    --     ["3808417022"] = 50, -- Basic Processor
    --     ["3808417021"] = 10, -- Uncommon Processor
    --     ["1080827609"] = 1,  -- Uncommon Antenna M
    --     ["4186205972"] = 10, -- Basic Power Transformer
    -- }

    local order = require(self.orderName)
    local buildList = {}

    self:addOrder(buildList, order.smelter, "Smelter")
    self:addOrder(buildList, order.metalwork, "Metalwork")
    self:addOrder(buildList, order.printer, "Printer")
    self:addOrder(buildList, order.chemical, "Chemical")
    self:addOrder(buildList, order.glass, "Glass")
    self:addOrder(buildList, order.electronics, "Electronics")

    local recipes = {}
    for id, _ in pairs(buildList) do
        table.insert(recipes, id)
    end

    self.buildList = buildList
    self.recipes = recipes

    modula:addTimer("onCheckMachines", 1.0)

    self:attachToScreen()
    industry:reportMachines()
    self:restartMachines()
end

function Module:onStopping()
    debugf("Auto Industry stopping.")
end

function Module:onContainerChanged(container)
    self.screen:send({ name = container:name(), value = container.percentage })
end

function Module:onScreenReply(reply)
end

function Module:onCheckMachines()
    self:restartMachines()
end

function Module:restartMachines()
    local industry = self.industry
    if industry then
        industry:withMachines(function(machine)
            self:restartMachine(machine)
        end)
    end
end

function Module:restartMachine(machine)
    if machine:isStopped() or machine:isMissingIngredients() or machine:isMissingSchematics() or machine:isPending() then
        local index = (1 + (machine.index or 0) % #self.recipes)
        machine.index = index
        local recipe = self.recipes[index]
        local order = self.buildList[recipe]
        if machine:label():find(order.machine) then
            if not machine:isStopped() then
                machine:stop()
            end

            if machine:setRecipe(recipe) == 0 then
                machine.target = recipe
                machine:start(order.quantity)
            end
        end
    elseif machine:isRunning() then
        if machine.actual ~= machine.target then
            debugf("Running '%s' for %s (%s).", system.getItem(machine.target).locDisplayName, machine:name(),
                machine:label())
            machine.actual = machine.target
        end
    end
end

function Module:onCommand(command, parameters)
    if command == "list" then
        local industry = modula:getService("industry")
        if industry then
            industry:reportMachines()
        else
            debugf("No industry service found.")
        end
    end
end

-- ---------------------------------------------------------------------
-- Internal
-- ---------------------------------------------------------------------


function Module:addOrder(buildList, itemsToAdd, type)
    for id, quantity in pairs(itemsToAdd) do
        buildList[id] = {
            quantity = quantity,
            machine = type,
        }
    end
end

function Module:attachToScreen()
    local service = modula:getService("screen")
    if service then
        local screen = service:registerScreen(self, false, self.renderScript)
        if screen then
            self.screen = screen
        end
    end
end

Module.renderScript = [[

containers = containers or {}

if payload then
    local name = payload.name
    if name then
        containers[name] = payload
    end
    reply = { name = name, result = "ok" }
end

local screen = toolkit.Screen.new()
local layer = screen:addLayer()
local chart = layer:addChart(layer.rect:inset(10), containers, "Play")

layer:render()
screen:scheduleRefresh()
]]

return Module
