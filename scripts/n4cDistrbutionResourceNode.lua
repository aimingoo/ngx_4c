-- register me(current master process) as resource client node
--	*) @see: sandpiper/tasks/init_unlimit_node.js
--	*) @see: sandpiper/tasks/init_worker_node.js
-- 
local t = {
	version = '2.0.0',
	scope = 'clients', -- run at ngx_cc master node only
}

local use_ngx_timer, tick = true

if use_ngx_timer then
	local sender = require('lib.Sender')
	local etcd_put_options = {method = 'PUT', headers = {Connection = "Keep-Alive"}} -- @see sender.lua
	tick = function (_, timeout, heartbeat_url)
		sender.send(heartbeat_url..'&value='..tostring(os.time()), etcd_put_options)
		ngx.timer.at(timeout, tick, timeout, heartbeat_url)	-- loop
	end
else
	tick = function(self)
		ngx_cc.remote(self.heartbeat_url..'&value='..tostring(os.time()), self.etcd_put_options)
	end
end

function t:run()
	local conf = n4c.configuration
	if not conf.n4c_resource_group then return end

	local nodeHost = assert(conf.n4c_external_host, 'invalid configuration n4c_external_host or none discovery') -- setting in init.lua
	local nodePort = tostring(route.cluster.master.port) -- setting at setWorker() in module/ngx_cc_core.lua
	local nodeAddr = nodeHost .. ((nodePort == '' or nodePort == '80') and "" or (":" .. nodePort))
	local nodeUniqueName = table.concat({nodeAddr, 'ngxcc', conf.default_channel_name}, '@')
	local nodeKey = conf.n4c_resource_group .. '/.' .. nodeUniqueName
	local dataKey = conf.n4c_resource_group .. '/' .. nodeUniqueName .. '/execute_task'
	local execute_task_uri = 'http://' .. nodeAddr .. conf.n4c_execute_uri
	local ok, resps = ngx_cc.remote(conf.etcd_server.url .. nodeKey .. '?value='..tostring(os.time()), { method = ngx.HTTP_PUT })
	if ok then -- if resp.status equ 201, the nodeKey was created
		local ok, resps = ngx_cc.remote(conf.etcd_server.url .. dataKey, {
			ctx = { cc_headers = {
				["Content-Type"] = "application/x-www-form-urlencoded; param=value",
			}},
			method = ngx.HTTP_PUT,
			body = 'value='..execute_task_uri,
		})
		local timeoutSeconds, retry = 15, 3
		local ttl = math.ceil(timeoutSeconds*retry)
		local heartbeat_url = conf.etcd_server.url .. nodeKey ..'?ttl='..tostring(ttl)..'&prevExist=true'

		-- start heartbeat
		--	*) @see promise_set_heartbeat() in sandpiper/tasks/init_worker_node.js
		if use_ngx_timer then
			ngx.timer.at(0, tick, timeoutSeconds, heartbeat_url)
		else
			route.tasks.push({
				name = 'resource node report',
				identifier = 'resourcenodereport',
				interval = timeoutSeconds,
				typ = 'normal', -- current module loaded in master only
				heartbeat_url = heartbeat_url,
				etcd_put_options = {method = 'PUT', cc_headers = {Connection = "Keep-Alive"}}, -- for ngx_cc
				callback = tick,
			})
		end
	else
		local err, msg = resps[1].status, resps[1].body
		ngx.log(ngx.ALERT, 'error '..tostring(err)..' in n4cDistrbutionResourceNode, '..(msg or 'unknow error'))
	end
end

return t