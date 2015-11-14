local t = {
	version = '2.0.0',
	scope = 'workers', -- root/clients/workers/root:workers
	desc = 'test: PEDT node'
}

local events = require('lib.Events'):new()

local JSON = require('testcase.lib.JSON')
local JSON_encode = function(...) return JSON:encode_pretty(...) end

local function errorResponse(reason)
	ngx.status = 500
	ngx.header.content_type = 'application/json'
	if type(reason) == 'table' then
		reason = JSON_encode(reason.reason or reason)
	else
		reason = JSON_encode(tostring(reason))
	end
	ngx.say(reason)
	ngx.exit(ngx.HTTP_OK)
end

-- for test only
events.on('RequestBegin', function(uri, method, params)
	if uri == '/n4c/test' then
		-- @see init_resource_center.js in $(sandpiper)/tasks
		local pathPart = '/com.wandoujia.n4c/sandpiper/nodes'
		local distributionScope = table.concat({'sandpiper', pathPart, '*'}, ':')

		-- @see t_tasks.js in $(sandpiper)/testcase
		local remote_taskId = 'task:c2eb2597e461aa3aa0e472f52e92fe0b'

		n4c:reduce(distributionScope, remote_taskId, 'a=1&b=2&c=3', function(_, taskResult)
			ngx.say(JSON_encode(taskResult))
			ngx.exit(ngx.HTTP_OK)
		end):catch(errorResponse)
	end
end)

-- for debugger only
events.on('RequestBegin', function(uri, method, params)
	if uri == '/n4c/system_routes' then
		n4c:require(params.key or "n4c.system.discoveries"):andThen(function(result)
			ngx.say(JSON_encode(result))
			ngx.exit(ngx.HTTP_OK)
		end):catch(errorResponse)
	end
end)

t.doRequestBegin = events["RequestBegin"]

return t