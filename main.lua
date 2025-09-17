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

    self:addOrder(buildList, order.refiner, "Basic Refiner")
    self:addOrder(buildList, order.smelter, "Basic Smelter")
    self:addOrder(buildList, order.metalwork, "Basic Metalwork Industry")
    self:addOrder(buildList, order.printer, "Basic 3D Printer")
    self:addOrder(buildList, order.chemical, "Basic Chemical industry")
    self:addOrder(buildList, order.glass, "Basic Glass Furnace")
    self:addOrder(buildList, order.electronics, "Basic Electronics industry")

    local recipes = {}

    for recipe, order in pairs(buildList) do
        local machineRecipe = recipes[order.machine]
        if not machineRecipe then
            machineRecipe = {}
            recipes[order.machine] = machineRecipe
        end
        table.insert(machineRecipe, recipe)
    end

    self.buildList = buildList
    self.recipes = recipes

    modula:addTimer("onCheckMachines", 1.0)

    self:attachToScreen()

    if self.reportMachines then
        industry:reportMachines()
    end

    local industry = self.industry
    if industry then
        industry:withMachines(function(machine)
            self:updateProblems(machine)
        end)
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
end

function Module:restartMachine(machine)
    if machine:isStopped() or machine:isMissingIngredients() or machine:isMissingSchematics() or machine:isPending() then
        local recipes = self.recipes[machine:label()]
        if not recipes or #recipes == 0 then
            debugf("No recipes for %s - %s", machine:label(), machine:name())
            return
        end

        local index = (1 + (machine.index or 0) % #recipes)
        machine.index = index
        local recipe = recipes[index]
        local buildOrder = self.buildList[recipe]
        if machine:label():find(buildOrder.machine) then
            if not machine:isStopped() then
                machine:stop()
            end

            if machine:setRecipe(recipe) == 0 then
                machine.target = recipe
                machine.actual = nil
                machine:start(buildOrder.quantity)
            end
        end
        self:updateProblems(machine)
    elseif machine:isRunning() then
        if machine.actual ~= machine.target then
            debugf("Running '%s' for %s (%s).", system.getItem(machine.target).locDisplayName, machine:name(),
                machine:label())
            machine.actual = machine.target
            self:updateProblems(machine)
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

    local newStatus
    if machine:isMissingIngredients() then
        local list = {}
        for n, input in pairs(machine:inputs()) do
            table.insert(list, string.format("%s %s", input.name, input.quantity))
        end
        newStatus = string.format("Needs: %s", table.concat(list, ", "))
    elseif machine:isMissingSchematics() then
        newStatus = "Needs Schematics"
    elseif machine:isFull() then
        newStatus = "Output Full"
    elseif machine:isRunning() then
        newStatus = "Running"
        debugf("Running '%s' - %s.", machine:label(), machine:mainProduct().name)
    end

    if newStatus then
        local product = machine:mainProduct()

        local key = product.name
        newStatus = string.format("%s %s", machine:simpleLabel(), newStatus)
        if problems[key] ~= newStatus then
            problems[key] = newStatus
            local screen = self.screen
            if screen then
                screen:send({ command = "status", status = { key = key, value = newStatus } })
            end
        end
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
        end
    end
end

Module.renderScript = [[

status = status or {}

if payload then

    if payload.command == "status" then
        status[payload.status.key] = payload.status.value
    end
    reply = { name = payload.command, result = "ok" }
end

local screen = toolkit.Screen.new()
local layer = screen:addLayer()

local cOK = toolkit.Color.new(0, 255, 0)
local cWarn = toolkit.Color.new(255, 0, 0)

local gotItems = false
local y = 40
for n, line in pairs(status) do
    local color
    if line == "Starting Industry..." then
        color = toolkit.white
    elseif string.find(line, "Running") then
        color = cOK
    else
        color = cWarn
    end

    local label = layer:addLabel({0, y, 300, y}, n, { fill = color })
    local value = layer:addLabel({300, y, 300, y}, line)
    y = y + 25
    gotItems = true
end

if not gotItems then
    local label = layer:addLabel({0, 0, 300, 40}, "Starting Industry...")
end

layer:render()
screen:scheduleRefresh()
]]

return Module
