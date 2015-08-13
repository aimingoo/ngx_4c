local t = {
	version = '2.0.0',
	scope = 'workers',
	desc = 'n4c framework core status report'
}

local mix = require('lib.mix')
local encode = require('cjson').encode
local decode = require('cjson').decode
local route_uri = '/'..n4c.configuration.default_channel_name..'/api'	-- /N4C/api

local counter = {
	active = 0,			-- non internal active only
	internal = 0,	 	-- internal active
--	total = nil,		-- by calculation, total request with subrequest
--	request = nil,		-- from n4c, total request(with internal), but without subrequest
--	subrequest = nil, 	-- from n4c, total subrequest
--	cast = nil, 		-- from n4c, only cast subrequest by ngx_cc
}
setmetatable(counter, { __index = n4c.stat() })

function t.doInternalRequestBegin()
	counter.internal = counter.internal + 1
end

function t.doInternalResponseEnd()
	counter.internal = counter.internal - 1
end

function t.doRequestBegin(uri, method, arg)
	counter.active = counter.active + 1

	if (uri == route_uri) and arg.coStatus then
		local no_redirected, r_status, r_resps = route.isInvokeAtPer()
		if not no_redirected then -- mix all
			local resultObject = {}
			if r_status then
				for _, resp in ipairs(r_resps) do
					mix(resultObject, resp and resp.body and decode(resp.body) or nil)
				end
			end
			ngx.say(encode(resultObject))
		else -- say status
			local c3 = counter
			ngx.say(encode({
				ngx_4c = { total=c3.request+c3.subrequest, active=c3.active, internal=c3.internal, subrequest=c3.subrequest, cast=c3.cast },
			}))
		end
		ngx.exit(ngx.HTTP_OK)
	end
end

function t.doResponseEnd()
	counter.active = counter.active - 1
end

return t