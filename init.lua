-----------------------------------------------------------------------------
-- NGX_4C v0.9.1
-- Author: aimingoo@wandoujia.com
-- Copyright (c) 2015.11
-- Descition:　n4c programming architecture, the Controllable, Computable and Communication Cluster in nginx.
--
-- Usage (in nginx.conf):
-- 	init_worker_by_lua 'n4c.startWorker();';	# -- Init Worker Processes
-- 	rewrite_by_lua 'n4c.doRequestBegin();';		# -- On Request Begin
-- 	body_filter_by_lua 'n4c.doBodyFilter();';	# -- On Response Chunks Filter
-- 	log_by_lua 'n4c.doSessionClose();';			# -- On Request End and Close Session 
--
-- launch demo.
-----------------------------------------------------------------------------
local DEFAULT_CONIFG_SUPER = { host='127.0.0.1', port='80' }
local DEFAULT_CONIFG_PEDT = {}
local mix = require('lib.Utils').mix

n4c = require('lib.Distributed'):new(DEFAULT_CONIFG_PEDT)

n4c = mix(n4c, {
	configuration = {
		default_channel_name = 'N4C',

		-- current node is resource node?
		-- n4c_resource_group = false,
		n4c_resource_group = '/com.wandoujia.n4c/ngx_4c/tundrawolf/nodes',

		-- resource management api
		n4c_resource_notify_uri = '/n4c/resource_notify/',
		n4c_resource_query_uri = '/n4c/resource_query/',

		-- PDET execute_task api
		--	*) the 'N4C' is configuration.default_channel_name
		n4c_execute_uri = '/N4C/invoke?execute=',
		n4c_external_host = '127.0.0.1',

		-- etcd service addr
		etcd_server = { url = 'http://127.0.0.1:4001/v2/keys' },
	},
	super = DEFAULT_CONIFG_SUPER,
	
})

-- a http client pool running in ngx.timer context
-- n4c.sender = require('lib.Sender')

-- init_worker launcher
--	*) or require from module:
--		n4c.startWorker = function() require('init_worker') end
n4c.startWorker = function()
	ngx.log(ngx.ALERT, 'in init_worker.lua')

	-- NGX_CC launcher, run at default channel
	ngx_cc = require('ngx_cc')
	ngx_cc.cluster.super = n4c.super
	route = ngx_cc:new(n4c.configuration.default_channel_name)

	-- default invokes for ngx_cc, optional
	require('module.invoke').apply(route)
	require('module.heartbeat').apply(route)
	require('module.invalid').apply(route)

	-- NGX_4C launcher, and multicast events
	local events = require('lib.Events'):new()
	require('ngx_4c').apply(n4c, events)
	n4c.register(require('scripts.n4cCoreFramework'))

	-- default tasks runner (drive tasks by per-request )
	--  *) ngx_tasks module loaded in heartbeat.lua, or custom by yourself
	--	*) call route.tasks:push() to append more task defines
	if route.tasks.run then
		events.on('RequestBegin', function() route.tasks:run() end)
	end

	-- NGX_4C framework scripts extra - status report
	n4c.register(require('scripts.n4cStatusReport'))

	-- NGX_4C framework scripts extra - Distrbution task architecture
	n4c.register(require('scripts.n4cDistrbutionTaskNode'))
	-- n4c.register(require('scripts.n4cNodeTimer'))
	require('module.n4c_executor').apply(route)
	require('module.n4c_resource_node').apply(route)

	-- NGX_4C Distrbution task architecture - extended routes
	n4c:require('n4c.system.discoveries'):andThen(function(discoveries)
		mix(discoveries, require('routes.routes_ngxcc').new(n4c.configuration.default_channel_name), true)
	end)

	-- testcases, or more business processes
	-- n4c.register(require('testcase.t_nginx_phases'))
	n4c.register(require('testcase.t_pedt'))
end