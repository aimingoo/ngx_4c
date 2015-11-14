-- 
-- register me(current worker process) as unlimited executor
--	*) @see: sandpiper/tasks/init_unlimit_node.js
--	*) @see: sandpiper/tasks/init_resource_center.js
-- 
local t = {
	version = '2.0.0',
	scope = 'workers' -- root/clients/workers/root:workers
}

local Promise = require('lib.Promise')

local events = require('lib.Events'):new()
local querystring_stringify = require('infra.httphelper').request_stringify
local distributed_request = require('infra.httphelper').distributed_request

local JSON = require('cjson')
local JSON_encode = JSON.encode
local JSON_decode = JSON.decode
local MD5 = ngx.md5
local CRC32 = ngx.crc32_short

local NGX_CC_CHANNEL_RESOURCES	-- set on t.run() by core_register(currentMod)
local GLOBAL_CACHED_ITEMS = {}	-- as resource center server

-- the <distributed> cache response body of downloaded task, and promised task instance
-- will cache in WORKER_CACHED_TASKS by Distributed.lua
local distributed = {}

-- @see: nats/infra/TaskCenter.js
local groupBasePath = '/com.wandoujia.n4c'
local token = string.format('%x', CRC32(groupBasePath))
local default_options = {
	-- task center at etcd
	etcdServer = { url = 'http://127.0.0.1:4001/v2/keys/N4C/task_center/tasks' },

	-- resource center run in nodejs
	--	*) @see $(sandpiper)/tasks/init_resource_center.js
	resourceCenterServer = {
		systemName = 'sandpiper',
		subscribeUrl = 'http://127.0.0.1:3232/n4c/'..token..'/subscribe',
		-- queryUrl = 'http://127.0.0.1:3232/n4c/'..token..'/query',
		groupBasePath = groupBasePath,
	},

	-- resource center client, or client/server for ngx_cc cluster
	clientVersion = '1.1',
	clientNotifyPath = n4c.configuration.n4c_resource_notify_uri, -- for ngx_cc cluster
	serverQueryPath = n4c.configuration.n4c_resource_query_uri, -- for ngx_cc cluster
}

local function errorResponse(reason)
	ngx.status = 500
	ngx.say(JSON_encode(reason))
	ngx.exit(ngx.HTTP_OK)
end

local SIGN_INVALID = {'INVALID RESOURCE'}
local function resolve_resource(resources, resId)
	if not resources[resId] then
		resources[resId] = {
			version = '1.0',
			updated = os.date(),
			value = SIGN_INVALID,
			subscriber = {}
		}
	end
	return resources[resId]
end

-- implemention: do_notify() in nats/tasks/init_resource_center.js
--	resId_for_ngx_cc: 	ngx_cc.<channel_name>.registed.<master/super/clients/workers>
--	resId_for_n4c:		n4c:<resId_for_ngx_cc>:*
events.on('RequestBegin', function(uri, method, params)
	local prefix = default_options.clientNotifyPath
	local n4c_resource_interface = string.gsub(prefix, '/$', "")
	if uri == n4c_resource_interface then
		local conf = default_options.resourceCenterServer
		local resId = ngx.unescape_uri(ngx.var.query_string)
		local isRoot, isMaster = route.isRoot(), (route.cluster.worker.port == route.cluster.router.port)
		local distributionScope = table.concat({conf.systemName, conf.groupBasePath..resId}, ':')
		if isMaster and GLOBAL_CACHED_ITEMS[distributionScope] then -- for all clients
			route.cc('/_/_'..uri, route.optionAgain('clients'))
		end
		if route.isInvokeAtPer() and GLOBAL_CACHED_ITEMS[distributionScope] then -- for all workers
			resolve_resource(GLOBAL_CACHED_ITEMS, distributionScope).value = SIGN_INVALID
		end
		ngx.say('Okay')
		ngx.exit(ngx.HTTP_OK)
	elseif string.find(uri, '^'..prefix) then -- for ngx_cc only
		local ngx_cc_registed_key = '^ngx_cc%.([^%.]+)%.registed%.([^%.]+)$'
		local resId = ngx.unescape_uri(string.sub(uri, string.len(prefix)+1))
		local channel, direction = string.match(resId, ngx_cc_registed_key)
		if channel and direction then -- internal notify for ngx_cc
			if route.isInvokeAtPer() then -- for all workers
				n4c:upgrade({system_route = { [resId] = false }})
				n4c:require(resId):andThen(function(resource)	-- try discovery again
					NGX_CC_CHANNEL_RESOURCES[resId] = resource
					ngx.say('Okay')
					ngx.exit(ngx.HTTP_OK)
				end):catch(errorResponse)
			else -- return after send to all workers
				ngx.say('Okay')
				ngx.exit(ngx.HTTP_OK)
			end
			-- NOTE: non implement
			-- if direction = 'clientport' then .. end
		end
	end
end)

-- implemention: e.on("query", ...) in sandpiper/tasks/init_resource_center.js
events.on('RequestBegin', function(uri, method, params)
	local prefix = default_options.serverQueryPath
	local prefix_rx, prefix_len = '^'..prefix, string.len(prefix)
	if string.find(uri, prefix_rx) then
		local resId = string.sub(uri, prefix_len+1)
		local distributionScope = resId .. ':*'
		n4c:require(distributionScope):andThen(function(resource)
			ngx.say(JSON_encode(resource))
			ngx.exit(ngx.HTTP_OK)
		end):catch(errorResponse)
	end
end)

----------------------------------------------------------------------------------------------------------------
-- task_register_center
--	*) register_task(taskDef)
-- 	*) download_task(taskId)
----------------------------------------------------------------------------------------------------------------
local function applyInvokes(invoke)
	--	/channel_name/invoke?download=task:md5
	invoke.download = function(route, channel, arg)
		local taskId = arg.download
		if not distributed[taskId] then
			-- check current node, code from rules/task.lua
			local isRoot, isMaster = route.isRoot(), (route.cluster.worker.port == route.cluster.router.port)

			-- download task from ectd, or master/super
			local ok, resps = false
			if isRoot then
				ok, resps = ngx_cc.remote(default_options.etcdServer.url .. '/' .. string.gsub(taskId, '^task:', ''))
			else
				local direction = isMaster and 'super' or 'master'
				ok, resps = route.cc('/_/invoke', { direction = direction, { args = { download = taskId }}})
			end
			if not ok then return errorResponse('"Cant download '..taskId..'"') end
			-- the <body> is JSON encoded
			distributed[taskId] = JSON_decode(resps[1].body).node.value
		end

		ngx.say(distributed[taskId])
		ngx.exit(ngx.HTTP_OK)
	end
end

local function n4c_download_task(taskId)
	return Promise.new(function(resolve, reject)
		local ok, resps = route.cc('/_/invoke', {direction = 'master', args = { download = taskId }})
		if ok then
			resolve(resps[1].body)
		else
			reject(resps and resps[1] and resps[1].body or ('"Cant download '..taskId..'"'))
		end
	end)
end

-- implemention: register_task() in sandpiper/infra/TaskCenter.js
--	*) ignore make_tasks_node() and make_client_node()
--	*) ignore recheck crc32
local function n4c_register_task(taskDef)
	return Promise.new(function(resolve, reject)
		local id, TASK = MD5(tostring(taskDef)), function(id) return default_options.etcdServer.url .. '/' .. id end
		local ok, resps = ngx_cc.remote(TASK(id), { method = 'POST', args = { prevExist = false }, data = taskDef })
		if ok then
			resolve('task:' .. id)
		else
			reject(resps and resps[1] and resps[1].body or ('"Cant register '..id..'"'))
		end
	end)
end

----------------------------------------------------------------------------------------------------------------
-- resource_status_center
--	*) require(resId)
----------------------------------------------------------------------------------------------------------------
-- transform parts to resId
--	*) @see: internal_require() in sandpiper/infra/ResourceCenter.js
local function internal_transform(parts)
	local systemPart, pathPart = string.match(parts, '^([^:]+):(.*)$')
	if not systemPart then return end

	-- compare systemName/systemPart/..., or check more resource center
	local conf = default_options.resourceCenterServer
	local basePath = conf.groupBasePath
	local basePathLen = string.len(basePath)
	if basePathLen > string.len(pathPart) then return end
	if basePath ~= string.sub(pathPart, 1, basePathLen) then return end  

	local resId = string.sub(pathPart, basePathLen+1)
	if resId == "" then
		return conf, "/"
	else
		if string.byte(resId, 1) ~= 47 then return end
		return conf, resId
	end
end

-- implemention: internal_subscribe() in sandpiper/infra/ResourceCenter.js
local function external_require(conf, resId)
	if not conf then return end

	local n4c_resource_interface = string.gsub(default_options.clientNotifyPath, '/$', "");
	return ngx_cc.remote(conf.subscribeUrl..'?'..resId, {
		method = ngx.HTTP_POST,  -- ngx_cc.remote() cant convert from 'POST'
		body = JSON_encode({
			['type'] = 'scope',
			['version'] = default_options.clientVersion,
			['receive'] = 'http://'.. ngx.var.server_addr ..
				':' .. route.cluster.master.port .. n4c_resource_interface,
		})
	})
end

-- implemention: internal_require() in sandpiper/infra/ResourceCenter.js
local function n4c_require_resource(parts)
	local resource = resolve_resource(GLOBAL_CACHED_ITEMS, parts)
	if resource.value == SIGN_INVALID then
		-- check current node, code from rules/task.lua
		local isRoot, isMaster = route.isRoot(), (route.cluster.worker.port == route.cluster.router.port)
		local ok, resps
		if isRoot and isMaster then
			ok, resps = external_require(internal_transform(parts))
		else
			-- query super and auto subscribe
			local direction = isMaster and 'super' or 'master'
			ok, resps = route.cc('/_/_' .. default_options.serverQueryPath .. parts, direction)
		end
		if ok then
			local result = resps and resps[1] and resps[1].body
			if result then resource.value = JSON_decode(result) end
		end
	end
	return resource.value ~= SIGN_INVALID and Promise.resolve(resource.value)
		or Promise.reject('Cant resolve resource ' .. parts)
end

----------------------------------------------------------------------------------------------------------------
-- main
----------------------------------------------------------------------------------------------------------------
function t:run()
	-- get reference of ngx_cc.resources
	NGX_CC_CHANNEL_RESOURCES = assert(ngx_cc.resources, 'cant find ngx_cc.resources')

	-- reset "__index" field in metatable of ngx_cc.resources
	setmetatable(NGX_CC_CHANNEL_RESOURCES, getmetatable({}))

	-- register invoke.download on defult route
	applyInvokes(route.invoke)

	-- upgrade n4c
	n4c:upgrade({
		task_register_center = {
			download_task = n4c_download_task,
			register_task = route.isRoot() and n4c_register_task or nil
		},
		resource_status_center = {
			require = n4c_require_resource
		},
		distributed_request = distributed_request
	})
end

t.doRequestBegin = events["RequestBegin"]

return t