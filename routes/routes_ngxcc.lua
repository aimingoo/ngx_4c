----------------------------------------------------------------------------------------
-- system routes for ngx_cc
----------------------------------------------------------------------------------------

-- @see lib/scripts/n4cDistrbutionTaskNode.lua
local ngx_cc_registed_key = '^ngx_cc%.([^%.]+)%.registed%.([^%.]+)$'
-- @see internal_parse_scope() in lib/Distributed.lua
local scope_tokens = '^([^:]+):(.*):([^:]+)$'

local function N4CKEY(key)
	return table.concat({'n4c', key, '*'}, ':')
end

local function N2CKEY(distributionScope)
	return ({ string.match(distributionScope, scope_tokens) })[2];
end

local PROTO = {
	clients = function(key)
		local channel, _ = string.match(key, ngx_cc_registed_key)
		local instance = ngx_cc.channels[channel]
		local registed = instance and instance.shared:get(key)
		if registed then
			local newValue = {}
			for host, port in string.gmatch(registed, '([^:,]+)([^,]*),?') do table.insert(newValue, {host, port}) end
			n4c:upgrade({system_route = { [N4CKEY(key)] = false, [key] = newValue }})
			return newValue2
		end
	end,

	workers = function(key)
		local channel, _ = string.match(key, ngx_cc_registed_key)
		local instance = ngx_cc.channels[channel]
		local registed = instance and instance.shared:get(key)
		if registed then
			local newValue, distributionScope = {}, table.concat({'n4c', key, '*'}, ':')
			for port in string.gmatch(registed, '(%d+)[^,]*,?') do table.insert(newValue, port) end
			n4c:upgrade({system_route = { [N4CKEY(key)] = false, [key] = newValue }})
			return newValue
		end
	end,

	master = function(key)
		local channel, _ = string.match(key, ngx_cc_registed_key)
		local instance = ngx_cc.channels[channel]
		local registed = instance and instance.shared:get('ngx_cc.'..channel..'.RouterPort')
		if registed then -- support dynamic 'master' direction
			local router = instance.cluster.router
			router.port, router.pid = string.match(registed, '^(%d+)/(%d+)')
			-- SKIP: the <host> is fix, dont update
			-- 	*) router.host = ngx_cc.cluster.master.host
			local distributionScope = table.concat({'n4c', key, '*'}, ':')
			local newValue = router.host..':'..router.port
			n4c:upgrade({system_route = { [N4CKEY(key)] = false, [key] = newValue }})
			return newValue
		end
	end,

	super = function(key)
		local channel, _ = string.match(key, ngx_cc_registed_key)
		local instance = ngx_cc.channels[channel]
		-- active by invoke.transferServer() in invoke.lua
		--	*) super.host/port reset by per-route's instance.transfer() in ngx_cc.lua
		if instance then -- support dynamic 'super' direction
			local super = instance.cluster.super
			local distributionScope = table.concat({'n4c', key, '*'}, ':')
			local newValue = super.host..':'..super.port
			n4c:upgrade({system_route = { [N4CKEY(key)] = false, [key] = newValue }})
			return newValue
		end
	end,
}

local function getDistributionScopeValues(channel, arr)
	local results = {}
	for _, addr in ipairs(arr) do
		table.insert(results, 'http://'..addr..'/'..channel..'/invoke?execute=')
	end
	return results
end

local function from_n2c_addrs(key)
	local n2ckey = N2CKEY(key)
	local channel, direction = string.match(n2ckey, ngx_cc_registed_key)
	local addrs, lists = {}, PROTO[direction](n2ckey) or {}
	for _, addr in ipairs(lists) do table.insert(addrs, table.concat(addr, ':')) end
	local newValue = getDistributionScopeValues(channel, addrs)
	if #newValue > 0 then n4c:upgrade({system_route = { [key] = newValue }}) end
	return newValue
end

local function from_n2c_ports(key)
	local n2ckey = N2CKEY(key)
	local channel, direction = string.match(n2ckey, ngx_cc_registed_key)
	local addrs, lists = {}, PROTO[direction](n2ckey) or {}
	local master_host = ngx_cc.channels[channel].cluster.master.host
	for _, port in ipairs(lists) do table.insert(addrs, table.concat({master_host, port}, ':')) end
	local newValue = getDistributionScopeValues(channel, addrs)
	if #newValue > 0 then n4c:upgrade({system_route = { [key] = newValue }}) end
	return newValue
end
local function from_n2c_string(key)
	local n2ckey = N2CKEY(key)
	local channel, direction = string.match(n2ckey, ngx_cc_registed_key)
	local newValue = getDistributionScopeValues(channel, {PROTO[direction](n2ckey)})
	if #newValue > 0 then n4c:upgrade({system_route = { [key] = newValue }}) end
	return newValue
end

return {
	new = function(channel)
		if not channel then return {} end
		channel = tostring(channel)
		return { -- clone functions
			["ngx_cc."..channel..".registed.clients"] = PROTO.clients,
			["ngx_cc."..channel..".registed.workers"] = PROTO.workers,
			["ngx_cc."..channel..".registed.super"]   = PROTO.super,
			["ngx_cc."..channel..".registed.master"]  = PROTO.master,

			["n4c:ngx_cc."..channel..".registed.clients:*"] = from_n2c_addrs,
			["n4c:ngx_cc."..channel..".registed.workers:*"] = from_n2c_ports,
			["n4c:ngx_cc."..channel..".registed.super:*"]   = from_n2c_string,
			["n4c:ngx_cc."..channel..".registed.master:*"]  = from_n2c_string,
		}
	end
}