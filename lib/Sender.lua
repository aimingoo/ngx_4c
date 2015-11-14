local http = require('resty.http')

local pool = {
	limit = 128,			-- max concurrent timer
	running = 0,			-- current running timer
	scheduling = 0,			-- current scheduling requests
	queue = {},				-- a queue lazyed requests
}

-- here, get args from pool.send(url, ...)
local default_headers = {
	-- ["accept"]			= "*/*",						-- reserved by cosocket
	-- ["user-agent"]		= "Resty/HTTP 0.1.0 (Lua)",		-- reserved by cosocket
	-- ["Connection"]		= "close",						-- default of HTTP/1.0
	["Content-Type"]	= "text/plain; charset=UTF-8",	-- for chana service
}

local http_request = function(client, opt, ...)
	local callback_chains = {...}
	local function callback(...)
		for _, cb in ipairs(callback_chains) do pcall(cb, client, opt, ...) end
	end
	callback(client:request(opt))
end

local function http_request_keep(pool, url, opts, ...)
	local client = http:new()
	opts = opts or {}
	http_request(client, {
		url = url,
		keepalive = 3*60*1000,	-- for resty.http only, maximal idle timeout (in milliseconds)
		headers = opts.headers or default_headers,
		method = opts.method,
		body = opts.body,
	})
end

function pool.tick(_, pool, queue)
	if not queue then
		queue, pool.queue = pool.queue, {}
	end

	pool.scheduling = pool.scheduling + #queue
	for _, args in ipairs(queue) do
		pool.scheduling = pool.scheduling - 1
		http_request_keep(pool, unpack(args))
	end

	if #pool.queue > 0 then
		ngx.timer.at(0, pool.tick, pool)
	else
		pool:release()
	end
end

function pool:require(args)
	if self.running < self.limit then
		self.running = self.running + 1
		return ngx.timer.at(0, self.tick, self, {args})
	else
		table.insert(self.queue, args)
	end
end

function pool:release()
	self.running = self.running - 1
end

return {
	send = function(...)
		pool:require({...})
	end
}