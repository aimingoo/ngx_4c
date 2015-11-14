-- 
-- clientport update notify for super
--	*) TODO: the 'cluster.report_clients' is false always, so the module invalid
-- 
local t = {
	version = '2.0.0',
	scope = 'workers' -- root/clients/workers/root:workers
}

local sender = require('lib.Sender')

local function tick(premature, timeout)
	if premature then
		-- Premature timer expiration happens when the NGINX worker process is trying to shut down,
		-- as in an NGINX configuration reload triggered by the HUP signal or in an NGINX server shutdown. 
		--	*) Now, accept zero timeout value on new ngx.timer.at() only.
		--	*) the <sender>  use 0-timeout only
		--	*) @see https://www.nginx.com/resources/wiki/modules/lua/#ngx-timer-at
		local prefix, opt = '/n4c/resource_query/', nil
		for channel, instance in pairs(ngx_cc.channels) do
			local cluster = instance.cluster
			if cluster.report_clients then
				local super = 'http://' .. cluster.super.host .. ':' .. cluster.super.port
				local key_registed_clientport = 'n4c.' .. channel .. '.registed.clientport'
				sender.send(super..prefix..key_registed_clientport, opt)
			end
		end
	else
		ngx.timer.at(timeout, tick, timeout)	-- loop
	end
end

function t:run()
	local timeoutSeconds = 12*3600
	ngx.timer.at(timeoutSeconds, tick, timeoutSeconds)
end

return t