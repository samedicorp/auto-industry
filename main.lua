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
    self.reportMachines = parameters.reportMachines or true
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
    self.machineList = {}

    -- self:addOrder(buildList, order.refiner, "Basic Refiner")
    -- self:addOrder(buildList, order.smelter, "Basic Smelter")
    -- self:addOrder(buildList, order.metalwork, "Basic Metalwork Industry")
    -- self:addOrder(buildList, order.chemical, "Basic Chemical industry")
    -- self:addOrder(buildList, order.chemical, "Uncommon Chemical industry")
    -- self:addOrder(buildList, order.uncommonChemicals, "Uncommon Chemical Industry")

    -- self:addOrder(buildList, order.glass, "Basic Glass Furnace")

    self:addOrder(buildList, order.electronics, "Basic Electronics industry")
    -- self:addOrder(buildList, order.electronics, "Uncommon Electronics Industry")
    -- self:addOrder(buildList, order.uncommonElectronics, "Uncommon Electronics Industry")

    -- self:addOrder(buildList, order.printer, "Basic 3D Printer")

    local machineList = self.machineList
    for machine, items in pairs(machineList) do
        local mInfo = system.getItem(machine)
        debugf("machine %s %s", mInfo.locDisplayName, machine)
    end

    industry:withMachines(function(machine)
        local machineClass = machine:itemId()
        local machineItems = machineList[machineClass]
        if machineItems then
            debugf("machine %s %s has orders:", machine:label(), machineClass)
            for _, item in ipairs(machineItems) do
                local itemInfo = system.getItem(tonumber(item.id))
                debugf("  - %s x%s", itemInfo.locDisplayName, item.quantity)
            end
        end
    end)


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

    -- modula:addTimer("onCheckMachines", 2.0)

    -- self:attachToScreen()

    -- if self.reportMachines then
    --     industry:reportMachines()
    -- end

    -- local industry = self.industry
    -- if industry then
    --     industry:withMachines(function(machine)
    --         self:updateProblems(machine)
    --     end)
    -- end

    -- self:restartMachines()
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
    elseif machine:isRunning() then
        if machine.actual ~= machine.target then
            debugf("Running '%s' for %s (%s).", system.getItem(machine.target).locDisplayName, machine:name(),
                machine:label())
            machine.actual = machine.target
        end
    end
    self:updateProblems(machine)
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
    local newDetail

    local product = machine:mainProduct()
    if not product then
        return
    end

    local order = self.buildList[toString(product.id)] or { quantity = 0 }
    if order.quantity == 0 then
        order.quantity = 1
        debugf("No order for %s (%s)", product.name, machine:name())
    end
    local batchCount = math.ceil(order.quantity / product.mainRecipe.quantity)

    if machine:isMissingIngredients() then
        local ingredients = {}
        if order then
            batchCount = order.quantity / product.mainRecipe.quantity
            debugf("%s x%s (%s batches) missing ingredients", product.name, order.quantity, batchCount)

            for n, input in pairs(product.mainRecipe.ingredients) do
                local iName = system.getItem(input.id).locDisplayName
                table.insert(ingredients, string.format("%s %s", iName, math.floor(input.quantity * batchCount)))
            end
        end
        newStatus = string.format("%s Needs Ingredients", machine:name())
        newDetail = table.concat(ingredients, ", ")
    elseif machine:isMissingSchematics() then
        newStatus = "Needs Schematics"
    elseif machine:isFull() then
        newStatus = "Output Full"
    elseif machine:isRunning() then
        newStatus = "Running"
        if order.quantity > 1 then
            newDetail = string.format("Making %s (%s batches) on %s", math.floor(order.quantity),
                math.floor(batchCount), machine:name())
        else
            newDetail = string.format("Making 1 on %s", machine:name())
        end
    elseif machine:isPending() then
        newStatus = "OK"
        local order = self.buildList[toString(machine:mainProduct().id)]
        if order then
            newDetail = string.format("x %s", math.floor(order.quantity))
        else
            newDetail = string.format("x %s", machine:mainProduct().id)
        end
    end

    if newStatus then
        local product = machine:mainProduct()

        local key = product.name
        if newDetail == nil then
            newDetail = machine:name()
        end
        if problems[key] ~= newStatus then
            problems[key] = newStatus
            local screen = self.screen
            if screen then
                screen:send({ command = "status", status = { key = key, value = newStatus, detail = newDetail } })
            end
        end
    end
end

function Module:addOrder(buildList, itemsToAdd, type)
    local machineList = self.machineList
    local industry = self.industry
    for id, quantity in pairs(itemsToAdd) do
        buildList[id] = {
            quantity = quantity,
            machine = type,
        }

        local p = industry:productForItem(tonumber(id))
        if p then
            local r = p:mainRecipe()
            if r then
                for n, producer in ipairs(r.producers) do
                    local itemList = machineList[producer]
                    if not itemList then
                        itemList = {}
                        machineList[producer] = itemList
                    end
                    table.insert(itemList, { id = id, quantity = quantity })
                end
            end
        end
    end
end

function Module:attachToScreen()
    local service = modula:getService("screen")
    if service then
        local screen = service:registerScreen(self, "main", "samedicorp.auto-industry.screens.main")
        if screen then
            self.screen = screen
        end
    end
end

return Module
