--[[

A small example showing how to use mod data on isoObjects without being an asshole
This file contains code for both client and server

It covers:
  - checking mod data without creating it and name spacing your keys
  - simple client command where the client asks and the server decides
  - validating everything on the server, including the object, distance and that the player really has the item
  - finding and validating objects by square+index
  - removing an item from a player's main inventory and syncing it
  - syncing mod data to nearby clients with transmitModData
  - adding a menu option with OnFillWorldObjectContextMenu including support for controllers
  - keeping command handlers in a local table

]]

-- Client Code (media/lua/client/LineWithTinFoil_Client.lua)

local function isLined(obj)
    -- hasModData doesn't create a table but getModData does
    -- check first, don't create mod data if you don't have to
    return obj:hasModData() and obj:getModData().TinFoil and obj:getModData().TinFoil.lined
end

local function askServerToLineWithFoil(player, obj)
    -- get and format args and send the command to the server
    local sq = obj:getSquare()
    sendClientCommand(player, "TinFoil", "lineContainer", {
        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        index = obj:getObjectIndex(),
        sprite = obj:getSprite() and obj:getSprite():getName(),
    })
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    local playerObj = getSpecificPlayer(playerNum)
    for _, obj in ipairs(worldobjects) do
        if obj:getContainer() then
            if isLined(obj) then
                if test then return ISWorldObjectContextMenu.setTest() end -- setTest is for controller users
                local option = context:addOption("Foil Lined", nil, nil)
                option.notAvailable = true
            elseif playerObj:getInventory():containsType("Base.Aluminum") then -- check main inv
                if test then return ISWorldObjectContextMenu.setTest() end
                context:addOption("Line with Foil", playerObj, askServerToLineWithFoil, obj)
            end
            return
        end
    end
end)


-- Server Code (media/lua/server/LineWithTinFoil_Server.lua)
if isClient() then return end

-- like PZ says, getting objects by index is fragile but it's the best way right now
-- if your mod creates the object, you can slap a unique ID in its mod data on the server before transmitting
-- ie: obj:getModData().myObjId = getRandomUUID()
-- and match on that instead of the sprite
 
-- we find the object with square+index and then double check the sprite
local function findObject(args)
    local sq = getCell():getGridSquare(args.x, args.y, args.z)
    if not sq then return nil end
    local objs = sq:getObjects()

    -- is the index in bounds?
    if args.index < 0 or args.index >= objs:size() then return nil end
    local obj = objs:get(args.index)
    
    -- does the obj we found match what we want?
    local sprite = obj:getSprite() and obj:getSprite():getName()
    if sprite ~= args.sprite then return nil end
    return obj
end

local Commands = {} -- keep your command handlers local

function Commands.lineContainer(player, args)
    -- validate everything on the server
    if type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number"
        or type(args.index) ~= "number" then return end

    local obj = findObject(args)
    if not obj or not obj:getContainer() then return end

    -- is the player close to the obj square?
    if player:getZ() ~= obj:getSquare():getZ() then return end
    if player:getSquare():DistTo(obj:getSquare()) > 2 then return end

    -- is the obj already lined?
    local modData = obj:getModData()
    if modData.TinFoil and modData.TinFoil.lined then return end

    -- does the player really have foil?
    local inv = player:getInventory() -- check main inv
    local foil = inv:getFirstType("Base.Aluminum")
    if not foil then return end
    
    -- remove foil from inventory
    inv:Remove(foil) -- remove foil from server or SP
    sendRemoveItemFromContainer(inv, foil) -- remove foil from player's client

    -- save and sync
    modData.TinFoil = { lined = true, by = player:getUsername() }
    obj:transmitModData() -- send the new mod data to nearby clients
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "TinFoil" then return end
    if Commands[command] then Commands[command](player, args or {}) end
end)
