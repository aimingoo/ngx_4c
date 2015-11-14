--
-- register n4c executor at default channel
--
local querydata_parse = require('infra.requestdata').parse

local JSON = require('cjson')
local JSON_encode = JSON.encode
local JSON_decode = JSON.decode

local function errorResponse(reason)
	ngx.status = 500
	ngx.say(JSON_encode(reason))
	ngx.exit(ngx.HTTP_OK)
end

local function submitTaskResult(taskResult)
	ngx.say(JSON_encode(taskResult))
	ngx.exit(ngx.HTTP_OK)
end

local function apply(invoke)
	--	/channel_name/invoke?execute=task:md5
	invoke.execute = function(route, channel, arg)
		local taskId, arguments = arg.execute, querydata_parse()
		arguments.execute = nil
		n4c:execute_task(taskId, arguments):andThen(submitTaskResult, errorResponse)
	end

	--	/channel_name/invoke?register=task:md5
	invoke.register = function(route, channel, arg)
		ngx.req.read_body()
		local loader = require('tools.taskloader'):new({publisher = n4c})  -- will call n4c.register_task
		local file_context = ngx.var.request_body
		-- the loadScript() will return self.publisher:register_task(taskDef)
		Loader:loadScript(file_context):andThen(submitTaskResult, errorResponse)
	end

	return invoke
end

return {
	apply = function(route)
		return apply(route.invoke)
	end
}