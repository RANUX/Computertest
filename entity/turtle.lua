
local FORMNAME_TURTLE_INVENTORY = "computertest:turtle:inventory:"
local FORMNAME_TURTLE_TERMINAL  = "computertest:turtle:terminal:"
local FORMNAME_TURTLE_UPLOAD    = "computertest:turtle:upload:"
local TURTLE_INVENTORYSIZE = 4*4

local function getTurtle(id) return computertest.turtles[id] end
local function isValidInventoryIndex(index) return 0 < index and index <= TURTLE_INVENTORYSIZE end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local function isForm(name)
        return string.sub(formname,1,string.len(name))==name
    end
    --minetest.debug("FORM SUBMITTED",dump(formname),dump(fields))
    if isForm(FORMNAME_TURTLE_INVENTORY) then
        local id = tonumber(string.sub(formname,1+string.len(FORMNAME_TURTLE_INVENTORY)))
        local turtle = getTurtle(id)
        if (fields.upload_code=="Upload Code") then
            minetest.show_formspec(player:get_player_name(),FORMNAME_TURTLE_UPLOAD..id,turtle:get_formspec_upload());
        elseif (fields.open_terminal=="Open Terminal") then
            minetest.show_formspec(player:get_player_name(),FORMNAME_TURTLE_TERMINAL..id,turtle:get_formspec_terminal());
        elseif (fields.factory_reset=="Factory Reset") then
            return not turtle:upload_code_to_turtle("",false)
        end
    elseif isForm(FORMNAME_TURTLE_TERMINAL) then
        if (fields.terminal_out ~= nil) then return true end
        local id = tonumber(string.sub(formname,1+string.len(FORMNAME_TURTLE_TERMINAL)))
        local turtle = getTurtle(id)
        turtle.lastCommandRan = fields.terminal_in
        local command = fields.terminal_in
        if command==nil or command=="" then return nil end
        command = "function init(turtle) return "..command.." end"
        local commandResult = turtle:upload_code_to_turtle(command, true)
        if (commandResult==nil) then
            minetest.close_formspec(player:get_player_name(),FORMNAME_TURTLE_TERMINAL..id)
            return true
        end
        commandResult = fields.terminal_in.." -> "..commandResult
        turtle.previous_answers[#turtle.previous_answers+1] = commandResult
        minetest.show_formspec(player:get_player_name(),FORMNAME_TURTLE_TERMINAL..id,turtle:get_formspec_terminal());
    elseif isForm(FORMNAME_TURTLE_UPLOAD) then
        local id = tonumber(string.sub(formname,1+string.len(FORMNAME_TURTLE_UPLOAD)))
        if (fields.button_upload == nil or fields.upload == nil) then return true end
        local turtle = getTurtle(id)
        return not turtle:upload_code_to_turtle(fields.upload,false)
    else
        return false--Unknown formname, input not processed
    end
    return true--Known formname, input processed "If function returns `true`, remaining functions are not called"
end)

--Code responsible for updating turtles every turtle_tick
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if (timer >= computertest.config.turtle_tick) then
        for _,turtle in pairs(computertest.turtles) do
            if turtle.coroutine then
                if coroutine.status(turtle.coroutine)=="suspended" then
                    --TODO check for fuel here
                    local status, result = coroutine.resume(turtle.coroutine)
                    minetest.log("coroutine stat "..dump(status).." said "..dump(result))
                    --elseif coroutine.status(turtle.coroutine)=="dead" then
                    --minetest.log("turtle #"..id.." has coroutine, but it's already done running")
                end
            elseif turtle.code then
                --minetest.log("turtle #"..id.." has no coroutine but has code! Making coroutine...")
                --TODO add some kinda timeout into coroutine
                turtle.coroutine = coroutine.create(function()
                    turtle.code()
                    init(turtle)
                end)
                --else
                --minetest.log("turtle #"..id.." has no coroutine or code, who cares...")
            end
        end
        timer = timer - computertest.config.turtle_tick
    end
end)
--Code responsible for generating turtle entity and turtle interface
minetest.register_entity("computertest:turtle", {
    initial_properties = {
        hp_max = 1,
        is_visible = true,
        makes_footstep_sound = false,
        physical = true,
        collisionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
        visual = "cube",
        visual_size = { x = 0.9, y = 0.9 },
        textures = {
            "computertest_top.png",
            "computertest_bottom.png",
            "computertest_right.png",
            "computertest_left.png",
            "computertest_back.png",
            "computertest_front.png",
        },
        automatic_rotate = 0,
        id = -1,
    },

    --MAIN TURTLE USER INTERFACE------------------------------------------
    get_formspec_inventory = function(turtle)
        return "size[12,5;]"
                .."button[0,0;2,1;open_terminal;Open Terminal]"
                .."button[2,0;2,1;upload_code;Upload Code]"
                .."button[4,0;2,1;factory_reset;Factory Reset]"
                .."set_focus[open_terminal;true]"
                .."list[".. turtle.inv_fullname..";main;8,1;4,4;]"
                .."background[8,1;1,1;computertest_inventory.png]"
                .."list[current_player;main;0,1;8,4;]";
    end,
    get_formspec_terminal = function(turtle)
        local previous_answers = turtle.previous_answers
        local parsed_output = "";
        for i=1, #previous_answers do parsed_output = parsed_output .. minetest.formspec_escape(previous_answers[i]).."," end
        --local saved_output = "";
        --for i=1, #previous_answers do saved_output = saved_output .. minetest.formspec_escape(previous_answers[i]).."\n" end
        return
        "size[12,9;]"
                .."field_close_on_enter[terminal_in;false]"
                .."field[0,0;12,1;terminal_in;;"..minetest.formspec_escape(turtle.lastCommandRan or "").."]"
                .."set_focus[terminal_in;true]"
                .."textlist[0,1;12,8;terminal_out;"..parsed_output.."]";
    end,
    get_formspec_upload = function(turtle)
        --TODO could indicate if code is already uploaded
        return
        "size[12,9;]"
                .."button[0,0;2,1;button_upload;Upload Code to #"..turtle.id.."]"
                .."field_close_on_enter[upload;false]"
                .."textarea[0,1;12,8;upload;;"..minetest.formspec_escape(turtle.codeUncompiled or "").."]"
                .."set_focus[upload;true]";
    end,
    upload_code_to_turtle = function(turtle, code_string,run_for_result)
        local function sandbox(code)
            --TODO sandbox this!
            --Currently returns function that defines init and loop. In the future, this should probably just initialize it using some callbacks
            if (code =="") then return nil end
            return loadstring(code)
        end
        turtle.codeUncompiled = code_string
        turtle.coroutine = nil
        turtle.code = sandbox(turtle.codeUncompiled)
        if (run_for_result) then
            --TODO run subroutine once, if it returns a value, return that here
            return "Ran"
        end
        return turtle.code ~= nil
    end,
    --MAIN END TURTLE USER INTERFACE------------------------------------------
    --- From 0 to 3
    set_heading = function(turtle,heading)
        heading = (tonumber(heading) or 0)%4
        if turtle.heading ~= heading then
            turtle.heading = heading
            turtle.object:set_yaw(turtle.heading * 3.14159265358979323/2)
            if (coroutine.running() == turtle.coroutine) then turtle:yield("Turning",true) end
        end
    end,
    get_heading = function(self)
        return self.heading
    end,
    on_activate = function(turtle, staticdata, dtime_s)
        --TODO use staticdata to load previous state, such as inventory and whatnot
        --Give ID
        computertest.num_turtles = computertest.num_turtles+1
        turtle.id = computertest.num_turtles
        turtle.heading = 0
        turtle.previous_answers = {}
        turtle.coroutine = nil
        turtle.fuel = 100
        --Give her an inventory
        turtle.inv_name = "computertest:turtle:".. turtle.id
        turtle.inv_fullname = "detached:".. turtle.inv_name
        local inv = minetest.create_detached_inventory(turtle.inv_name,{})
        if inv == nil or inv == false then error("Could not spawn inventory")end
        inv:set_size("main", TURTLE_INVENTORYSIZE)
        if turtle.inv ~= nil then inv.set_lists(turtle.inv) end
        turtle.inv = inv
        -- Add to turtle list
        computertest.turtles[turtle.id] = turtle
    end,
    on_rightclick = function(self, clicker)
        if not clicker or not clicker:is_player() then return end
        minetest.show_formspec(clicker:get_player_name(), FORMNAME_TURTLE_INVENTORY.. self.id, self:get_formspec_inventory())
    end,
    get_staticdata = function(self)
    --    TODO convert inventory and internal code to string and back somehow, or else it'll be deleted every time the entity gets unloaded
        minetest.debug("Deleting all data of turtle")
    end,
    turtle_move_withHeading = function (turtle,numForward,numRight,numUp)
        local new_pos = turtle:get_nearby_pos(numForward,numRight,numUp)
        --Verify new pos is empty
        if (new_pos == nil or minetest.get_node(new_pos).name~="air") then
            turtle:yield("Moving",true)
            return false
        end
        --Take Action
        turtle.object:set_pos(new_pos)
        turtle:yield("Moving",true)
        return true
    end,
    get_nearby_pos = function(turtle, numForward, numRight, numUp)
        local pos = turtle:get_pos()
        if pos==nil then return nil end -- To prevent unloaded turtles from trying to load things
        local new_pos = vector.new(pos)
        if turtle:get_heading()%4==0 then new_pos.z=pos.z-numForward;new_pos.x=pos.x-numRight; end
        if turtle:get_heading()%4==1 then new_pos.x=pos.x+numForward;new_pos.z=pos.z-numRight; end
        if turtle:get_heading()%4==2 then new_pos.z=pos.z+numForward;new_pos.x=pos.x+numRight; end
        if turtle:get_heading()%4==3 then new_pos.x=pos.x-numForward;new_pos.z=pos.z+numRight; end
        new_pos.y = pos.y + (numUp or 0)
        return new_pos
    end,
    mine = function(turtle, nodeLocation)
        if nodeLocation == nil then return false end
        local node = minetest.get_node(nodeLocation)
        if (node.name=="air") then return false end
        --Try sucking the inventory (in case it's a chest)
        turtle:suckBlock(nodeLocation)
        local drops = minetest.get_node_drops(node)
        --NOTE This violates spawn protection, but I know of no way to mine that abides by spawn protection AND picks up all items and contents (dig_node drops items and I don't know how to pick them up)
        minetest.remove_node(nodeLocation)
        for _, iteminfo in pairs(drops) do
            local stack = ItemStack(iteminfo)
            if turtle.inv:room_for_item("main",stack) then
                turtle.inv:add_item("main",stack)
            end
        end
        turtle:yield("Mining",true)
        return true
    end,
    useFuel = function(turtle)
        if turtle.fuel > 0 then
            turtle.fuel = turtle.fuel - 1;
        end
    end,
--    MAIN TURTLE INTERFACE    ---------------------------------------
    yield = function(turtle,reason,useFuel)
        -- Yield at least once
        if (coroutine.running() == turtle.coroutine) then
            coroutine.yield(reason)
        end
        --Use a fuel if requested
        if useFuel then turtle:useFuel() end
    end,

    moveForward = function(turtle)  return turtle:turtle_move_withHeading( 1, 0, 0) end,
    moveBackward = function(turtle) return turtle:turtle_move_withHeading(-1, 0, 0) end,
    moveRight = function(turtle)    return turtle:turtle_move_withHeading( 0, 1, 0) end,
    moveLeft = function(turtle)     return turtle:turtle_move_withHeading( 0,-1, 0) end,
    moveUp = function(turtle)       return turtle:turtle_move_withHeading( 0, 0, 1) end,
    moveDown = function(turtle)     return turtle:turtle_move_withHeading( 0, 0,-1) end,

    turnLeft = function(turtle)     return turtle:set_heading(turtle:get_heading()+1) end,
    turnRight = function(turtle)    return turtle:set_heading(turtle:get_heading()-1) end,

    mineForward = function(turtle)  return turtle:mine(turtle:get_nearby_pos    (1,0,0)) end,
    mineBackward = function(turtle)  return turtle:mine(turtle:get_nearby_pos   (-1,0,0)) end,
    mineRight = function(turtle)  return turtle:mine(turtle:get_nearby_pos      (0,1,0)) end,
    mineLeft = function(turtle)  return turtle:mine(turtle:get_nearby_pos       (0,-1,0)) end,
    mineUp = function(turtle)  return turtle:mine(turtle:get_nearby_pos         (0,0,1)) end,
    mineDown = function(turtle)  return turtle:mine(turtle:get_nearby_pos       (0,0,-1)) end,

    get_pos = function(turtle)      return turtle.object:get_pos() end,
    get_fuel = function(turtle) return turtle.fuel end,

    --[[    Sucks inventory (chest, node, furnace, etc) at nodeLocation into turtle
    @returns true if it sucked everything up]]
    suckBlock = function(turtle, nodeLocation)
        local suckedEverything = true
        local nodeInventory = minetest.get_inventory({type="node", pos=nodeLocation})
        if not nodeInventory then
            return false --No node inventory
        end
        for listName,listStacks in pairs(nodeInventory:get_lists()) do
            for stackI,itemStack in pairs(listStacks) do
                if turtle.inv:room_for_item("main",itemStack) then
                    local remainingItemStack = turtle.inv:add_item("main",itemStack)
                    nodeInventory:set_stack(listName, stackI, remainingItemStack)
                else
                    suckedEverything = false
                end
            end
        end
        return suckedEverything
    end,

    -- MAIN INVENTORY COMMANDS--------------------------
    ---    TODO drops item onto ground
    itemDrop = function(turtle,itemslot)
    end,
    --- TODO Returns ItemStack on success or nil on failure
    ---Ex: turtle:itemGet(3):get_name() -> "default:stone"
    itemGet = function(turtle,itemslot)
        if isValidInventoryIndex(itemslot) then
            return turtle.inv:get_stack("main",itemslot)
        end
        return nil
    end,
    ---    Swaps itemstacks in slots A and B
    itemMove = function(turtle, itemslotA, itemslotB)
        if (not isValidInventoryIndex(itemslotA)) or (not isValidInventoryIndex(itemslotB)) then
            turtle:yield("Inventorying")
            return false
        end

        local stackA = turtle.inv:get_stack("main",itemslotA)
        local stackB = turtle.inv:get_stack("main",itemslotB)

        minetest.debug(dump(stackA:to_string()))
        minetest.debug(dump(stackB:to_string()))

        turtle.inv:set_stack("main",itemslotA,stackB)
        turtle.inv:set_stack("main",itemslotB,stackA)

        turtle:yield("Inventorying")
        return true
    end,
    ---    TODO Pushes item into forward-facing chest
    ---    TODO after getting this working, add a general function with whitelists
    itemPush = function(turtle, itemslot, listname)
        listname = listname or "main"
    end,
    ---    TODO craft using top right 3x3 grid, and put result in itemslotResult
    itemCraft = function(turtle,itemslotResult)
    end,
    itemRefuel = function(turtle,itemslot)
        local burntime = 0--TODO get burntime
--        If fuels are defined like this, how do I get the burntime back, given an item?
--[[        minetest.register_craft("",{
            type = "fuel",
            recipe = "bucket:bucket_lava",
            burntime = 60,
            replacements = {{"bucket:bucket_lava", "bucket:bucket_empty"}},
        })]]

        turtle.fuel = turtle.fuel + burntime * computertest.config.fuel_multiplier
    end,
    --    MAIN TURTLE INTERFACE END---------------------------------------
})
