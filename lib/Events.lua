-----------------------------------------------------------------------------
-- Multicast Events in lua v1.0.1
-- Author: aimingoo@wandoujia.com
-- Copyright (c) 2015.08
--
-- The Multicast module from NGX_4C architecture
--	1) N4C is programming framework.
--	2) N4C = a Controllable & Computable Communication Cluster architectur.
--
-- Usage:
--	E = Events.new()						-- or, Events.new()
--	E.on("Begin", function(arg1) .. end)	-- add event listen, or E("Begin", ..)
--	E.on("Begin", ..)						-- and more(multi cast)
--	E.Begin(arg1);							-- fire event
--	E.on("TopBeginning", E.Begin)			-- concat events
--	E.TopBeginning(arg1);					-- ...
--
-- Note:
--	1. dynamic append handle(push func in event loop) supported, and valid
--	   immediate(active with current session/request).
--	2. Dont cache null event! use Events.isNull(e) to check it.
--
-- History:
--	2015.08.11	release v1.0.1, full testcases, minor fix and publish on github
--	2015.05		release v1.0.0
-----------------------------------------------------------------------------

local NullEvent = setmetatable({}, {
	__call = function() return true end  -- fake pcall return value
})

local MetaEvent = {
	__call = function(e, ...)
		-- return pcall(function(...)
		--	for _, e in ipairs(me) do e(...) end
		-- end, ...)
		for _, h in ipairs(e) do pcall(h, ...) end
	end
}

local MetaEvents = {
	__index = function(me, name) return name=='on' and me or NullEvent end,
	__call = function(me, name, func)
		local e = rawget(me, name)
		if not e then
			rawset(me, name, setmetatable({func}, MetaEvent))
		else
			table.insert(e, func)
		end
	end
}

local Events = {
	new = function() return setmetatable({}, MetaEvents) end,
	isNull = function(me) return me == NullEvent end,
}

return Events