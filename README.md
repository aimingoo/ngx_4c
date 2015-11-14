# ngx_4c
n4c programming architecture, a Controllable, Computable and Communication Cluster implementation in nginx.

n4c depend ngx_cc to build communication cluster, use Multi-cast events drive application framework. it invoke by nginx phases, and built-in standard API in the framework.

about N4C architecture  @see [n4c project](https://github.com/aimingoo/n4c).

main features:
- events - very simple, cool!
- consistency event loop
- simple and extendible location route
- ngx_cc integrated, support cluster communication
- modular application framework, scripting and dynamic loadding

###Table of Contents
  * [Install &amp; Usage](#install--usage)
  * [Events and event loop](#events-and-event-loop)
  * [ngx_cc integrated](#ngx_cc-integrated)
  * [PEDT: Distribution task module](#pedt-distribution-task-module)
  * [N4C standard interfaces](#n4c-standard-interfaces)
  * [N4C core framework](#n4c-core-framework)
  * [Customizable headers in ngx_cc, or sub-request](#customizable-headers-in-ngx_cc-or-sub-request)
  * [Event handles](#event-handles)
  * [History](#history)

# Install & Usage
if need ngx_cc integrate, you must recomplie nginx. the detail in here: [ngx_cc environment requirements](https://github.com/aimingoo/ngx_cc#environment). no dependency require of other case.

for ngx_cc integrated, please try [test in the nginx environment](https://github.com/aimingoo/ngx_cc#4-test-in-the-nginx-environment) first, and clone the ngx_4c project from github, get all sub-modules.
```bash
> cd ~
> git clone https://github.com/aimingoo/ngx_4c

> cd ~/ngx_4c/lib
> bash ./SUB_MODULES.sh
```
and run testcase:
```bash
#(into builded nginx directory)
# run bin/nginx with -p parament to set prefix
#	- will start nginx with $prefix/conf/nginx.conf by default
> sudo sbin/nginx -p "${HOME}/ngx_4c/nginx"
```
> note1: add these paths to nginx.conf in your project:
> * $prefix../?.lua;
> * $prefix../lib/?.lua;

> note2: if require other module(ex: ngx_cc or tundrawolf), push them to $(ngx_4c)/lib/, and append paths into nginx.conf:
> * $prefix../lib/ngx_cc/?.lua;
> * $prefix../lib/tundrawolf/?.lua;

# Events and event loop
the Events is a lua module, it's multi-cast, multi-handles and lightweight event framework. @see:
>	[https://github.com/aimingoo/Events](https://github.com/aimingoo/Events)

in ngx_4c, the event loop drive by nginx phases. there is workflow for the loop:
![n4c event loop](https://github.com/aimingoo/ngx_cc/wiki/images/n4c_event_loop.png)

next demo use ngx_4c as a web application framework.

 - nginx.conf

```conf
http {
	## path&dict config
	lua_package_path ...;

	## n4c core framework and runtime
	# ------------------------------------
	# init global n4c setting and n4c.startWorker() launcher
	init_by_lua_file 'init.lua';

	# init for per-worker
	init_worker_by_lua 'n4c.startWorker();';	# -- Init Worker Processes

	# standard handles
	rewrite_by_lua 'n4c.doRequestBegin();';		# -- On Request Begin
	body_filter_by_lua 'n4c.doBodyFilter();';	# -- On Response Chunks Filter
	log_by_lua 'n4c.doSessionClose();';			# -- On Request End and Close Session 
	# ------------------------------------

	server {
		listen 80;
	}
}
```

 - init.lua

```lua
n4c = {}
n4c.startWorker = function()
	-- NGX_4C launcher, with multicast events
	local events = require('lib.Events'):new()
	require('ngx_4c').apply(n4c, events)

	events.on('RequestBegin', function(uri, method, params)
		if uri == '/hello' then
			ngx.say('hello, world.')
		end
	end)

	events.on('RequestBegin', function(uri, method, params)
		if uri == '/hi' then
			ngx.say('hi, ' .. params.name or 'guest')
		end
	end)
end
```

- run and test

```bash
# start nginx
# 	> sudo sbin/nginx -c ...

> curl 'http://localhost/hello'
hello, world.

> curl 'http://localhost/hi'
hi, guest

> curl 'http://localhost/hi?name=aimingoo'
hi, aimingoo
```

# ngx_cc integrated

(1) insert ngx_cc standard config
- see: $(ngx_4c)/nginx/conf/nginx.conf
- see: [enable per-worker for listen](https://github.com/aimingoo/ngx_cc#4-test-in-the-nginx-environment)
- see: [ngx_cc locations](https://github.com/aimingoo/ngx_cc#locations-in-nginxconf)

(2) standard init.lua
- see: $(ngx_4c)/init.lua

(3) put webapp_demo.lua to $(ngx_4c)/scripts

```lua
-- /scripts/webapp_demo.lua
local t = {}
t.doRequestBegin = function(uri, method, params)
	if uri == '/test' then
		local atPerWorker, r_ok, r_resps = route.isInvokeAtPer();
		if atPerWorker then
			ngx.say('hi, work at ', ngx.worker.pid())
		else
			ngx_cc.say(r_ok, r_resps)
		end
	end)
end
return t
```

at last, add next line into init.lua
```lua
n4c.register(require('scripts.webapp_demo'))
```
and run test:
```bash
> curl 'http://localhost/test'
hi, work at xxxx
hi, work at xxxx
hi, work at xxxx
hi, work at xxxx
```
# PEDT: Distribution task module

(1) require tundrawolf project
```bash
> cd lib
> run SUB_MODULES.sh
```

(2) update nginx.conf
```conf
.....
lua_package_path '.....;$prefix../lib/tundrawolf/?.lua;;';
```

(3) load distribution task modules
> @see $(ngx_4c)/init.lua

```lua
...
	-- NGX_4C framework scripts extra - Distrbution task architecture
	n4c.register(require('scripts.n4cDistrbutionTaskNode'))
	-- n4c.register(require('scripts.n4cNodeTimer'))
	require('module.n4c_executor').apply(route)
	require('module.n4c_resource_node').apply(route)

	-- NGX_4C Distrbution task architecture - extended routes
	n4c:require('n4c.system.discoveries'):andThen(function(discoveries)
		mix(discoveries, require('routes.routes_ngxcc').new(n4c.configuration.default_channel_name), true)
	end)
...
```

(4) testcase
load test module, @see $(ngx_4c)/init.lua
```conf
...
	-- testcases, or more business processes
	n4c.register(require('testcase.t_pedt'))
...
```
and test in shell:
```bash
> # 1. test environment: install etcd and sandpiper for testcases
> brew install etcd etcdctl
> etcd
> cd ~
> git clone 'http://github.com/aimingoo/sandpiper'
> cd sandpiper
> npm install
> # 2. run sandpiper as daemon
> npm start
> # 3. start new shell, run again
> node testcase/t_tasks.js

> # 4. start new shell, and run nginx with test config.conf
> # 	- $(nginx_home) is home directory of nginx
> cd $(nginx_home)/sbin
> sudo nginx ./nginx -p "${HOME}/ngx_4c/nginx"

> # 5. run testcase
> curl -s 'http://localhost/n4c/test'
[ {
  "a": "1",
  "b": "2",
  "c": "3",
  "info": "HELLO",
  "p1": "default value"
} ]
> curl -s 'http://localhost/n4c/system_routes'
{
  "n4c.system.discoveries": ::function::,
  "n4c:ngx_cc.N4C.registed.clients:*": ::function::,
  "n4c:ngx_cc.N4C.registed.master:*": ::function::,
  "n4c:ngx_cc.N4C.registed.super:*": ::function::,
  "n4c:ngx_cc.N4C.registed.workers:*": ::function::,
  "ngx_cc.N4C.registed.clients": ::function::,
  "ngx_cc.N4C.registed.master": ::function::,
  "ngx_cc.N4C.registed.super": ::function::,
  "ngx_cc.N4C.registed.workers": ::function::
}
```

# N4C standard interfaces

> @see: $(ngx_4c)/ngx_4c.lua

```lua
n4c = {
	-- for ngx_cc
	configuration = {
		default_channel_name = 'N4C',	-- channel name of ngx_cc
		max_buffered_length = 4096,		-- for n4c cached repsponse body

		-- more configuration of n4c expand or 3rd modules
		n4c_resource_group = '..',
		n4c_resource_notify_uri = '..',
		n4c_resource_query_uri = '..',
		n4c_execute_uri = '..',
		n4c_external_host = '..',
		etcd_server = { url = '..' },
		..
	},
	super = DEFAULT_CONIFG_SUPER,		-- default is 127.0.0.1:80

	-- n4c worker launcher
	startWorker = function() .. end,

	-- Events and event loop
	doRequestBegin = function(uri, method, params) .. end,
	doBodyFilter = function(chunk, eof) .. end,
	doSessionClose = function() .. end,

	-- privated
	doResponseEnd = function(uri, bodySize, buffered) .. end,

	-- utilities or helper
	stat = function() .. end,  -- return a stat object
	register = function(scriptObject, ...) .. end, -- load scriptObject, and run main method with arguments
}
```

# N4C core framework

> @see: $(ngx_4c)/scripts/n4cCoreFramework.lua

the core framework include features:
- buffered response body
 - try 4k only, settings n4c.configuration.max_buffered_length
- ngx.ctx.get_resp_object() will try return JSON object
 - lazy decode, high performances
 - result is cached in current request/session/context
- implementation /channel_name/api?transferServer interface for ngx_cc

# Customizable headers in ngx_cc, or sub-request
when send sub-request in nginx.conf, you cant dynamic setting/update headers.

but, with ngx_4c, you can call ngx_cc to send a customizable headers to upstream by proxy_pass. the feature provided by "n4c.doRequestBegin(true)":
```conf
	location ~ ^/([^/]+)/cast {
		...

		## n4c core: cc_headers custom support
		rewrite_by_lua 'n4c.doRequestBegin(true);';

		...
	}
```
so, now, you call ngx_cc command with "cc_headers":
```lua
route.cc(aUri, {
	direction = 'workers',
	ctx = {cc_headers = {
		["Accept-Language"] = 'en-US',
		["Access-Control-Max-Age"] = 24*3600
	}}
})
```

or, use ngx.location.capture() without ngx_cc:
```lua
local aUri = '/test/headers'
ngx.location.capture(aUri, {
	ctx = {cc_headers = { .. }}
})
```
and, you must update nginx.conf for his location settings:
```conf
	location /test/headers {
		rewrite_by_lua 'n4c.doRequestBegin(true);';
	}
```
# Event handles
please handle Events by registed script module. the list of handles for per event:
```text
doRequestBegin = function(uri, method, params)
------ 
   doRequestBegin
   doInternalRequestBegin

doBodyFilter = function(chunk, eof)
------ 
   doBodyFilter
   doInternalBodyFilter

doResponseEnd = function(uri, bodySize, buffered)
------ 
   doResponseEnd
   doInternalResponseEnd

doSessionClose = function()
------ 
   doSessionClose
   doInternalSessionClose
```
the n4c.doResponseEnd() is privated, non publish interface but can handle it.

please read these cases for register handles:

> @see: $(ngx_4c)/scripts/*
>
> @see: $(ngx_4c)/testcase/t_nginx_phases.lua

# History
```text
2015.11	release v0.9.1, support PEDT distribution task
	- require tundrawolf (a implement of PEDT specification )
	- support PEDT resource/task node
	- support ngx_cc node/worker processes as PEDT nodes

2015.08	release v0.9.0
	- N4C programming architecture standard interfaces and examples
	- support ngx_cc integrated
	- support customizable headers for ngx_cc or sub-requests
```
