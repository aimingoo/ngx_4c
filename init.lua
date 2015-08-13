-----------------------------------------------------------------------------
-- NGX_4C v0.9.0
-- Author: aimingoo@wandoujia.com
-- Copyright (c) 2015.05
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

n4c = {
	configuration = {
		default_channel_name = 'N4C'
	},
	super = DEFAULT_CONIFG_SUPER
}

-- init_worker launcher
--	*) or require from module:
--		n4c.startWorker = function() require('init_worker') end
n4c.startWorker = function()
	ngx.log(ngx.ALERT, 'in init_worker.lua')

	-- NGX_CC launcher, run at default channel
	ngx_cc = require('ngx_cc')
	ngx_cc.cluster.super = n4c.super
	route = ngx_cc:new(n4c.configuration.default_channel_name)

	-- default invokes by ngx_cc, optional
	require('module.invoke').apply(route)
	require('module.heartbeat').apply(route)
	require('module.invalid').apply(route)

	-- NGX_4C launcher, with multicast events
	local events = require('lib.Events'):new()
	require('ngx_4c').apply(n4c, events)
	n4c.register(require('scripts.n4cCoreFramework'))

	-- default tasks runner (drive tasks by per-request )
	--  *) ngx_tasks module loaded in heartbeat.lua, or custom by yourself
	--	*) call route.tasks:push() to append more task defines
	if route.tasks.run then
		events.on('RequestBegin', function() route.tasks:run() end)
	end

	-- NGX_4C framework scripts extra
	n4c.register(require('scripts.n4cStatusReport'))
	-- n4c.register(require('scripts.n4cDynamicChannel'))
	-- n4c.register(require('scripts.n4cTaskProcess'))

	-- testcases, or more business processes
	n4c.register(require('testcase.t_nginx_phases'))
end