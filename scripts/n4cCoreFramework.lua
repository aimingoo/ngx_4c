local t = {
	version = '2.0.0',
	scope = 'workers',
	desc = 'n4c web application service core framework'
}

local decode = require('cjson').decode
local events = require('lib.Events'):new()
local max_buffered_length = n4c.configuration.max_buffered_length or 4096
local route_uri = '/'..n4c.configuration.default_channel_name..'/api'	-- /N4C/api

-- try response body buffered
function t.doBodyFilter(chunk, eof)
	local maxBufferedLength, ctx = max_buffered_length, ngx.ctx;
	local chunkLen, buffLen = chunk and chunk:len() or 0, ctx.BufferedLength or 0;

	-- dont replace as 'ngx.var.body_bytes_sent':
	ctx.ContentLength = (ctx.ContentLength or 0) + chunkLen

	if (chunkLen > 0) and (buffLen < maxBufferedLength) then
		if (buffLen == 0) then -- for first thunk only
			if chunkLen <= maxBufferedLength then
				ctx.buffered, ctx.BufferedLength = chunk, chunkLen
			else -- full
				ctx.buffered, ctx.BufferedLength = chunk:sub(1, maxBufferedLength), maxBufferedLength
			end
		else -- append chunks to buffered
			local nLen = maxBufferedLength - buffLen
			if chunkLen <= nLen then
				ctx.buffered, ctx.BufferedLength = ctx.buffered .. chunk, buffLen + chunkLen
			else -- full
				ctx.buffered, ctx.BufferedLength = ctx.buffered .. chunk:sub(1, nLen), maxBufferedLength
			end
		end
	end
end

-- inject ngx.ctx.get_resp_object(), try decode response body as JSON, and cache it.
events.on('RequestBegin', function(uri, method, params)
	local maped = {}
	local maper = function(index, f)
		return (index ~= nil) and
			(maped[index] or rawset(maped, index, f(index))[index]) or nil
	end

	-- maped json.decode resp_body
	ngx.ctx.get_resp_object = function()
		local ok, result = pcall(maper, ngx.ctx.buffered, decode)
		return ok and result or nil
	end
end)

-- invoke /_/api?transferServer at super 
events.on('RequestBegin', function(uri, method, params)
	if (uri == route_uri) and params.transferServer then
		ngx_cc.transfer(params.to, params.channels or '*', params.clients or '*')
		ngx.say('Okay')
		ngx.exit(ngx.HTTP_OK)
	end
end)

t.doRequestBegin = events.RequestBegin

return t