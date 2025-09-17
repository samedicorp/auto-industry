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
    self.reportMachines = parameters.reportMachines or false
    self.problems = {}
    self.problemsChanged = true
end

-- ---------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------

function Module:onStart()
    debugf("Auto Industry started.")

    self:attachToScreen()
    local industry = modula:getService("industry")
    self.industry = industry


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

    if self.reportMachines then
        industry:reportMachines()
    end

    self:restartMachines()
end

function Module:onStopping()
    debugf("Auto Industry stopping.")
end

function Module:onContainerChanged(container)
    self.screen:send({ name = container:name(), value = container.percentage })
end

function Module:onScreenReply(reply)
    -- printf("reply: %s", reply)
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

    self:updateStatus()
end

function Module:restartMachine(machine)
    self:updateProblems(machine)
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

function Module:updateProblems(machine)
    local problems = self.problems
    local key = machine:label()
    local changed = false

    local newStatus
    if machine:isMissingIngredients() then
        newStatus = "Needs Ingredients"
    elseif machine:isMissingSchematics() then
        newStatus = "Needs Schematics"
    elseif machine:isFull() then
        newStatus = "Output Full"
    elseif machine:isRunning() then
        newStatus = "Running"
    end

    if newStatus then
        newStatus = string.format("%s making %s", newStatus, machine:mainProduct().name)
        if problems[key] ~= newStatus then
            problems[key] = newStatus
            self.problemsChanged = true
        end
    end
end

function Module:updateStatus(status)
    local screen = self.screen
    local status = {}

    if screen and self.problemsChanged then
        local problems = self.problems
        self.problemsChanged = false
        for key, problem in pairs(problems) do
            table.insert(status, string.format("%s: %s\n", key, problem))
        end

        if #status == 0 then
            table.insert(status, "All machines operational.")
        end

        screen:send({ command = "status", status = status })
        self.lastStatus = status
    end
end

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
        local screen = service:registerScreen(self, "main", self.renderScript)
        if screen then
            self.screen = screen
            self:updateStatus()
        end
    end
end

Module.renderScript = [[

status = status or {}

if payload then

    if payload.command == "status" then
        status = payload.status
    end
    reply = { name = payload.command, result = "ok" }
end

local screen = toolkit.Screen.new()
local layer = screen:addLayer()

if not status or #status == 0 then
    table.insert(status, "Starting Industry...")
end

local cOK = toolkit.Color.new(0, 255, 0)
local cWarn = toolkit.Color.new(255, 0, 0)

local y = 40
for n, line in ipairs(status) do
    local color
    if line == "Starting Industry..." then
        color = toolkit.white
    elseif line:find("Running") then
        color = cOK
    else
        color = cWarn
    end

    local label = layer:addLabel({0, y, 300, y}, line, { fill = color })
    y = y + 25
end

layer:render()
screen:scheduleRefresh()
]]

return Module
