--[[
        Copyright © 2018, Rubenator
        All rights reserved.

        Redistribution and use in source and binary forms, with or without
        modification, are permitted provided that the following conditions are met:

            * Redistributions of source code must retain the above copyright
              notice, this list of conditions and the following disclaimer.
            * Redistributions in binary form must reproduce the above copyright
              notice, this list of conditions and the following disclaimer in the
              documentation and/or other materials provided with the distribution.
            * Neither the name of xivbar nor the
              names of its contributors may be used to endorse or promote products
              derived from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
        ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
        WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
        DISCLAIMED. IN NO EVENT SHALL SirEdeonX BE LIABLE FOR ANY
        DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
        (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
        LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
        ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
        (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
        SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]
_addon.author = 'Cliff, Based on Rubenator, Icy, Garyfromwork and inspired by Kouryuu'
_addon.command = 'vw'
_addon.name = 'vWalk'
_addon.version = '1.0.0c'

-- adjust the settings xml
-- added the save command so you don't have to use the old move command anymore. Just drag the box where you want it and //vw save


local res = require('resources')
require('luau')
local texts = require('texts')
local packets = require("packets")
local math = require('math')
local config = require('config')

local defaults ={
	defaultOn = true,
	str = "[vw]",
	text = {
		pos = {
			x = 10,
			y = 1
		},
		flags={draggable=true},
	},
}

local settings = config.load(defaults)
local targetPos = nil
local on = settings.defaultOn

--setup text
function setup_text(text)
    text:bg_alpha(255)
    text:bg_visible(true)
    text:font('Courier New')
    text:size(24)
    text:color(255,255,255,255)
    text:stroke_alpha(200)
    text:stroke_color(20,20,20)
    text:stroke_width(2)
	text:show()
end

local display_box = function()
    return '%s':format(settings.str and settings.str or "[vw]")
end

text = texts.new(display_box(), settings.text, settings)
setup_text(text)
settings:save("all")
text:text("[vw]")

local autoTracking = false
local autoTrackingAngle = 0

function stopTracking()
	targetPos = nil
end

function newPosition(x,y,directionID, distance)
	local angle
	if directionID ~= 0 then
		angle = (8-directionID) * math.pi / 4
	else
		angle = 0
	end
	local dx = distance*math.cos(angle)
	local dy = distance*math.sin(angle)
	return x+dx, y+dy
end

function getDistance(x,y)
	local me = windower.ffxi.get_mob_by_target('me')
	local cx, cy = math.abs(me.x-x), math.abs(me.y-y)
	return math.sqrt(cx*cx+cy*cy)
end


local compass = {"E", "NE", "N","NW","W","SW", "S", "SE"}
function getDirection(x,y)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me then return end
	
	local dx, dy = x-me.x, y-me.y
	local angle = math.atan(dy/dx)
	if dx < 0 then
		angle = angle + math.pi
	elseif dx >= 0 and dy < 0 then
		angle = angle+math.pi*2
	end
	local index = math.floor(angle/(math.pi/4)+0.5)+1
	if index > #compass then
		index = 1
	end
	return compass[index], angle, angle/(math.pi/8)
end

minDist = 999
lastDist = 0
stuckPoint = 0

windower.register_event('prerender', function(...)
	if not on then return end
	if on and targetPos then
		local direction = getDirection(targetPos.x, targetPos.y)
		if not direction then
			text:text("[vw]")
			return 
		end
		
		local directionString
		if #direction == 1 then
			direction = direction .. " "
		end
		local distance = getDistance(targetPos.x, targetPos.y)
		local distanceString = string.format("%0.1f", distance)
		settings.str = direction .. " " .. distanceString
		
		if distance < 2 then
			settings.str = direction .. " SIT"
            if autoTracking then
                windower.ffxi.run(false)
                windower.send_command('input /heal on;wait 1;input /heal off')
            end
		end
		text:text(settings.str)
        
        if autoTracking then
            diff = math.abs(lastDist - distance)
            if diff ~=0 and diff < 0.17 then--sutcked
                stuckPoint = stuckPoint +1
                -- log('s '..stuckPoint..'delta='..math.abs(lastDist - distance))
                if stuckPoint > 100 then--Sutcked
                    log('Stuck... Please help...')
                    -- windower.play_sound(''..windower.addon_path..'error.mp3')
                    windower.ffxi.run(false)
                    autoTracking = false
                    -- windower.send_command('input /heal on;wait 1;input /heal off')
                end
            else
                stuckPoint = 0
            end
            if distance - minDist >2 then--Overrun
                windower.ffxi.run(false)
                windower.send_command('input /heal on;wait 1;input /heal off')
            end
            if distance < minDist then
                minDist = distance
            end
            lastDist = distance
        end
	elseif not on then
		text:text("[vw]")
	end
end)

windower.register_event('keyboard', function(dik)
    if T{1,17,30,31,32}:contains(dik) then--keyboard to stop auto tracking
        if autoTracking then
            autoTracking = false
            log('keyboard interrupted, stopping.')
        end
    end
    
end)

windower.register_event('zone change', function(new, old)
    stopTracking()
	text:text("[vw]")
end)

-- inspect = require('inspect')
-- require('logger')
windower.register_event('incoming chunk', function(id,original,modified,injected,blocked)
	if not on then return end
    if id == 0x2a then -- Heal message. NOTE: Packet also triggered by other events such as zoning into abyssea, must check for proper ID below
		stopTracking()
        local packet = packets.parse('incoming', original)
		local directionID
		local distance
		-- Message ID: 40803 -- possibly "no light"
        if packet['Param 1'] and res.key_items[packet['Param 1']] and res.key_items[packet['Param 1']].en:endswith('abyssite') then
			-- none in the vicinity
			stopTracking()
			text:text(". . .")
			--log(inspect(packet))
		elseif packet['Param 4'] and res.key_items[packet['Param 4']] and res.key_items[packet['Param 4']].en:endswith('abyssite') then			
			local me = windower.ffxi.get_mob_by_target('me')
			local x,y = me.x, me.y
			--print(me.x,me.y, "me")
            directionID = packet['Param 2'] --[[
                0 = 'East'
                1 = 'Southeast'
         x      2 = 'South'
                3 = 'Southwest'
                4 = 'West'
                5 = 'Northwest'
                6 = 'North'
                7 = 'Northeast' --]]
            distance = packet['Param 3']			
			local newx,newy = newPosition(x,y, directionID, distance)
			--print(newx, newy, "target")
			--print(getDistance(newx, newy), "distance")
			--local dir, angle, segment = getDirection(newx, newy)
			--print("dir", dir, "angle", angle, "segment", segment)
			-- print(direction, distance)
			targetPos = {}
			targetPos.x = newx
			targetPos.y = newy
            handleAutoTacking(directionID, distance)
            minDist = 999
        end
    --[[elseif id == 0x0E8 then
		if windower.ffxi.get_player().status ~= 33 then
			targetPos = nil
			text:text("")
		end]]
	end
	
end)
require('coroutine')

windower.register_event('status change', function(new, old)
    local s = windower.ffxi.get_mob_by_target('me')
    -- log('n:'..new..' o'..old)
    if new == 0 and old == 33 then --standing from rest
    --TODO: How to handle cannot rest if hit by mob
        if autoTracking then
            log('auto running...')
            coroutine.sleep(4)
            windower.ffxi.run(autoTrackingAngle)
        end
    end
end)

function handleAutoTacking (dir, dist)
    -- 0 = 'East'
    -- 1 = 'Southeast'
    -- 2 = 'South'
    -- 3 = 'Southwest'
    -- 4 = 'West'
    -- 5 = 'Northwest'
    -- 6 = 'North'
    -- 7 = 'Northeast'
    autoTracking = false
	
	if dir==7 then
		angle = 7*math.pi/4
	elseif dir==5 then
		angle = 5*math.pi/4
	elseif dir==3 then
		angle = 3*math.pi/4
	elseif dir==1 then
		angle = math.pi/4
	elseif dir==0 then
		angle = 0
	elseif dir==4 then
		angle = math.pi
	elseif dir==6 then
		angle = 3*math.pi/2
	elseif dir==2 then
		angle = math.pi/2
	end
    windower.ffxi.turn(angle)
    autoTrackingAngle = angle
    
    if dist == 45 or dist==0 then
        return
    end

    log('Auto tracking start!!! Distance='..dist)
    autoTracking = true
end


windower.register_event('addon command', function(command, ...)
    if command then
		command = command:lower()

        if command == "save" then
            settings:save("all")
            log('settings saved')
        else--debug
            autoTracking = true
            windower.ffxi.run(autoTrackingAngle)
        end
	end
end)


windower.register_event('load', function()
    log('=================loaded=================')
end)
