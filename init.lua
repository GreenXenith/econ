--[[

	The MIT License (MIT)

	Copyright (C) 2019 GreenXenith/GreenDimond

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to
	deal in the Software without restriction, including without limitation the
	rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
	sell copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in
	all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
	IN THE SOFTWARE.

]]--

econ = {}
local storage = minetest.get_mod_storage()

dofile(minetest.get_modpath("econ").."/settings.lua")

-- Create card texture
local function card_texture()
	local line = "econ_card_line.png^[colorize:"..econ.card.line_color..":255"
	local logo = "[combine:16x16:2,4="..econ.bank.logo
	local name = "econ_card_name.png^[colorize:"..econ.card.name_color..":255"

	return string.format("(%s)^(%s)^(%s)^(%s)", line, logo, name, "econ_card_overlay.png")
end

minetest.register_craftitem("econ:card", {
	description = econ.card.name,
	inventory_image = econ.card.bg.."^[mask:econ_card_bg.png",
	inventory_overlay = card_texture(),
	stack_max = 1,
	on_drop = function() end,
})

minetest.register_craftitem("econ:coin", {
	description = econ.coin.name,
	inventory_image = econ.coin.texture,
	stack_max = econ.coin.max,
})

-- Currency unit label
local function unit(amount)
	if econ.coin.prefix then
		return econ.coin.unit..tostring(amount)
	else
		return tostring(amount)..econ.coin.unit
	end
end

-- ATM display
local function set_form(pos, display)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	if not display then
		display = {name = "", balance = ""}
	end
	inv:set_size("card", 1*1)
	inv:set_size("coin", 1*1)
	local form = ([[
		size[8,9]
		image[0.1,0.1;1,1;%s]
		label[1.2,0;%s]
		button[5.5,2;2,1;request;Get Card]
		label[5.5,2.9;Colorize:]
		scrollbar[5.5,3.3;2,0.3;horizontal;r;1000]
		label[5.3,3.2;R]
		scrollbar[5.5,3.6;2,0.3;horizontal;g;1000]
		label[5.3,3.5;G]
		scrollbar[5.5,3.9;2,0.3;horizontal;b;1000]
		label[5.3,3.8;B]
		list[context;card;4.5,2;1,1;]
		listring[current_name;card]
		listring[current_player;main]
		label[4.7,2.2;Card]
		list[context;coin;2.5,2;1,1;]
		listring[current_name;coin]
		listring[current_player;main]
		label[2.7,2.2;Coin]
		button[0.5,2;2,1;withdraw;Withdraw]
		field[0.8,3.5;2,1;amount;Amount;0]
		field_close_on_enter[amount;false]
		label[2.5,2.9;Name: %s]
		label[2.5,3.2;Balance: %s]
		list[current_player;main;0,5;8,4;]
	]]):format(econ.bank.logo, econ.bank.name, display.name, tostring(display.balance))
	meta:set_string("formspec", form)
end

-- ATM
minetest.register_node("econ:machine", {
	description = "Machine",
	drawtype = "mesh",
	mesh = "econ_machine.obj",
	tiles = {"econ_machine.png^[combine:48x32:21,5="..econ.bank.logo},
	selection_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5},
	},
	collision_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5},
	},
	paramtype2 = "facedir",
	groups = {cracky = 3, oddly_breakable_by_hand = 1},
	on_construct = function(pos)
		minetest.get_meta(pos):set_string("infotext", econ.bank.name.." ATM")
		set_form(pos)
	end,
	can_dig = function(pos)
		local inv = minetest.get_meta(pos):get_inventory()
		return inv:is_empty("coin", 1) and inv:is_empty("card", 1)
	end,
	on_receive_fields = function(pos, formname, fields, sender)
		local inv = minetest.get_meta(pos):get_inventory()
		local name = sender:get_player_name()
		-- Clear current information when leaving the ATM
		if fields.quit then
			set_form(pos)
			return
		end
		-- Get a new card
		if fields.request and inv:is_empty("card") then
			local stack = ItemStack("econ:card")
			local meta = stack:get_meta()
			meta:set_string("owner", name)
			meta:set_string("description", econ.card.name.." owned by "..name)
			inv:add_item("card", stack)
			local smeta = sender:get_meta()
			-- Apply given coin, if any, to account
			if not inv:is_empty("coin") then
				smeta:set_int("balance", smeta:get_int("balance") + inv:get_stack("coin", 1):get_count())
				inv:set_stack("coin", 1, "")
			end
			set_form(pos, {name = name, balance = unit(smeta:get_int("balance"))})
		end
		-- Withdrawl
		if fields.withdraw or fields.amount and not inv:is_empty("card") then
			local owner = inv:get_stack("card", 1):get_meta():get_string("owner")
			-- Make sure withdrawer is the card owner
			if name ~= owner then
				return
			end
			-- Valid amount?
			if not fields.amount or not tonumber(fields.amount) or tonumber(fields.amount) < 0 then
				return
			end
			fields.amount = math.floor(tonumber(fields.amount) + 0.5)
			local meta = sender:get_meta()
			-- Does the account have enough?
			if fields.amount > meta:get_int("balance") then
				return
			end
			local stack = ItemStack("econ:coin "..fields.amount)
			-- Add to player inventory if possible, otherwise add to coin slot
			if sender:get_inventory():room_for_item("main", stack) then
				sender:get_inventory():add_item("main", stack)
			else
				inv:add_item("coin", stack)
			end
			meta:set_int("balance", meta:get_int("balance") - fields.amount)
			set_form(pos, {name = owner, balance = unit(meta:get_int("balance"))})
		end
		-- Personalize card
		if (fields.r or fields.g or fields.b) and not (fields.withdraw or fields.request or fields.key_enter_field) and not inv:is_empty("card") then
			local stack = inv:get_stack("card", 1)
			local meta = stack:get_meta()
			if name ~= meta:get_string("owner") then
				return
			end
			local color = minetest.rgba(tonumber(fields.r:sub(5)) * 0.255, tonumber(fields.g:sub(5)) * 0.255, tonumber(fields.b:sub(5)) * 0.255)
			inv:remove_item("card", stack)
			meta:set_string("color", color)
			inv:add_item("card", stack)
		end
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if listname == "card" then
			if stack:get_name() ~= "econ:card" then
				return 0
			end
			return 1
		elseif listname == "coin" then
			-- This is to handle shift-clicking
			if stack:get_name() == "econ:card" then
				local inv = minetest.get_meta(pos):get_inventory()
				if inv:is_empty("card") then
					inv:add_item("card", stack)
					if player:get_player_name() ~= stack:get_meta():get_string("owner") then
						-- Mask balance if not owner
						set_form(pos, {name = stack:get_meta():get_string("owner"), balance = "?"})
					else
						set_form(pos, {name = stack:get_meta():get_string("owner"), balance = unit(player:get_meta():get_int("balance"))})
					end
				else
					return 0
				end
				return -1
			elseif stack:get_name() ~= "econ:coin" then
				return 0
			end
			return stack:get_count()
		end
	end,
	allow_metadata_inventory_move = function()
		return 0
	end,
	on_metadata_inventory_put = function(pos, listname, index, stack, player)
		local name = player:get_player_name()
		if listname == "card" then
			if name ~= stack:get_meta():get_string("owner") then
				-- Mask balance if not owner
				set_form(pos, {name = stack:get_meta():get_string("owner"), balance = "?"})
				return
			end
			set_form(pos, {name = stack:get_meta():get_string("owner"), balance = unit(player:get_meta():get_int("balance"))})
		elseif listname == "coin" and stack:get_name() == "econ:coin" then
			local inv = minetest.get_meta(pos):get_inventory()
			local card = inv:get_stack("card", 1):get_meta()
			-- Add to balance if card owner
			if name ~= card:get_string("owner") or inv:is_empty("card") then
				return
			end
			local meta = player:get_meta()
			meta:set_int("balance", meta:get_int("balance") + stack:get_count())
			inv:set_stack("coin", 1, "")
			set_form(pos, {name = card:get_string("owner"), balance = unit(meta:get_int("balance"))})
		end
	end,
	on_metadata_inventory_take = function(pos, listname, index, stack, player)
		if listname == "card" then
			-- Clear info
			set_form(pos)
		end
	end,
})

-- The coin recipe is calculated based on the mass of a standard gold bar (438.9 ounces).
-- Assuming each coin is 1 ounce, 2 gold ingots should produce roughly 878 coins.
-- We fudge this up to 999 for stack purposes.
minetest.register_craft({
	output = "econ:coin 999",
	type = "shapeless",
	recipe = {"default:gold_ingot", "default:gold_ingot"},
})

minetest.register_craft({
	output = "econ:machine",
	recipe = {
		{"default:tin_ingot", "default:glass", "default:tin_ingot"},
		{"default:tin_ingot", "default:paper", "default:tin_ingot"},
		{"default:tin_ingot", "econ:coin", "default:tin_ingot"},
	}
})
