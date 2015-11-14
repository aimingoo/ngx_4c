--
-- reset invoke.setWorker to load n4cDistrbutionResourceNode module
--	*) invoke.setWorker is core action, and register in ngx_cc/module/ngx_cc_core.lua
-- 	*) n4cDistrbutionResourceNode module need load by master/routePort node because use 'clients' scope
--	*) check 'master/routePort' after 'success_initialized' in ngx_cc_core.lua
--

local injected = setmetatable({}, {__call = function(injected, name, ...)
	if injected[name] then injected[name](...) end
end})

local function apply(invoke)
	local prefix = n4c.configuration.n4c_resource_notify_uri

	local function isPer(cluster)
		return cluster.worker.port == ngx.var.server_port
	end

	local function ADDR(cluster, port)
		return 'http://' .. cluster.master.host .. ':' .. tostring(port)
	end

	local function workers_invalid(route, channel, arg)
		-- 'cached "workers" invalid' notify, for /channel_name/invoke?registerWorker
		-- 		*) <self> is master process(per-worker)
		local router_port_invalid, cluster = false, route.cluster
		if cluster.router.port == cluster.worker.port then -- master only
			local key, value = 'ngx_cc.'..channel..'.RouterPort', cluster.worker.port .. '/' .. cluster.worker.pid
			router_port_invalid = route.shared:get(key) ~= value
			if router_port_invalid then -- master(RouterPort) updated
				route.shared:set(key, value)
			end
		end

		-- notify my self and waiting return
		local resId_workers, current, opt = 'ngx_cc.'..channel..'.registed.workers', cluster.worker.port, {}
		route.remote(ADDR(cluster, current)..prefix..resId_workers, opt)

		-- notify all
		route.cc('/_/_'..prefix..resId_workers, 'workers')
		if router_port_invalid then
			route.cc('/_/_'..prefix..('ngx_cc.'..channel..'.registed.master'), 'workers')
		end
	end

	-- /channel_name/invoke?registerWorker=xx
	--	*) 'cached "workers" invalid' notify
	invoke.registerWorker = function(route, ...)
		pcall(injected, 'register_worker', route, ...)
		if isPer(route.cluster) then workers_invalid(route, ...) end
	end

	-- /channel_name/invoke?invalidWorker=port
	--	*) 'cached "workers" invalid' notify
	invoke.invalidWorker = function(route, channel, arg)
		pcall(injected, 'invalid_worker', route, channel, arg)
		if isPer(route.cluster) and (arg.invalidWorker == ngx.ctx.invalidWorker) then workers_invalid(route, channel, arg) end
	end

	-- SUPER:PORT/channel_name/invoke?reportHubPort=xxx
	--	*) 'cached "clients" invalid' notify
	invoke.reportHubPort = function(route, channel, arg)
		pcall(injected, 'report_hubport', route, channel, arg)
		if isPer(route.cluster) then
			route.cc('/_/_'..prefix..('ngx_cc.'..channel..'.registed.clients'), 'workers')
		end
	end

	-- /channel_name/invoke?invalidClient=ip:port
	--	*) 'cached "clients" invalid' notify
	invoke.invalidClient = function(route, channel, arg)
		pcall(injected, 'invalid_client', route, channel, arg)
		if isPer(route.cluster) and arg.invalidClient == ngx.ctx.invalidClient then
			route.cc('/_/_'..prefix..('ngx_cc.'..channel..'.registed.clients'), 'workers')
		end
	end

	-- /channel_name/invoke?transferServer=xxx:xxx
	--	*) 'super invalid' notify
	invoke.transferServer = function(route, ...)
		pcall(injected, 'transfer_server', route, ...)
		if isPer(route.cluster) then
			route.remote(ADDR(route.cluster.worker.port)..prefix..('ngx_cc.'..channel..'.registed.super'))
		end
	end

	-- /channel_name/invoke?setWorker&lsof=p14739%20n*:80%20n*:8080
	--	*) load distrbution resource node module
	invoke.setWorker = function(...)
		pcall(injected, 'set_worker', ...)
		local isRoot, isMaster = route.isRoot(), (route.cluster.worker.port == route.cluster.router.port)
		if isMaster then
			n4c.register(require('scripts.n4cDistrbutionResourceNode'))
		end
	end

	return invoke
end

return {
	apply = function(route)
		local invoke = route.invoke
		injected.register_worker, injected.invalid_worker = invoke.registerWorker, invoke.invalidWorker
		injected.report_hubport, injected.invalid_client = invoke.reportHubPort, invoke.invalidClient
		injected.set_worker, injected.transfer_server = invoke.setWorker, invoke.transferServer
		return apply(invoke)
	end
}