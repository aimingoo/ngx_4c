# ngx_4c
n4c programming architecture, a Controllable, Computable and Communication Cluster implementation in nginx.

n4c depend ngx_cc to build communication cluster, use Multi-cast events drive application framework. it invoke by nginx phases, and built-in standard API in the framework.

main features:
> events - very simple, cool!
> consistency event loop
> simple and extendible location route
> ngx_cc integrated, support cluster communication
> modular application framework, scripting and dynamic loadding

# Install & Usage
you need recomplie nginx for ngx_cc, detail in here: [ngx_cc environment requirements](https://github.com/aimingoo/ngx_cc#environment).

try [test in the nginx environment](https://github.com/aimingoo/ngx_cc#4-test-in-the-nginx-environment) first, please.

next step, clone the ngx_4c project from github, get all sub-modules.
```
> cd ~
> git clone https://github.com/aimingoo/ngx_4c

> cd ~/ngx_4c/lib
> bash ./SUB_MODULES.sh
```
and run testcase:
```
#(into builded nginx directory)
# run bin/nginx with -p parament to set prefix
#	- will start nginx with $prefix/conf/nginx.conf by default
> sudo sbin/nginx -p ~/ngx_4c/nginx
```

# Events and event loop
the Events is a lua module, it's multi-cast, multi-handles and lightweight event framework. @see:
>	[https://github.com/aimingoo/Events](https://github.com/aimingoo/Events)

in ngx_4c, the event loop drive by nginx phases. there is workflow for the loop:
![](http://)

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
n4c.startWorker = function()
	-- NGX_4C launcher, with multicast events
	local events = require('lib.Events'):new()
	require('ngx_4c').apply(n4c, events)

	events.on('RequestBegin', function(uri, method, arg)
		if uri == '/hello' then
			ngx.say('hello, world.')
		end
	end)

	events.on('RequestBegin', function(uri, method, arg)
		if uri == '/hi' then
			ngx.say('hi, ' .. arg.name or 'guest')
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

1. insert ngx_cc standard config
> @see: $(ngx_4c)/nginx/conf/nginx.conf
> @see: [enable per-worker for listen](https://github.com/aimingoo/ngx_cc#4-test-in-the-nginx-environment)
> @see: [ngx_cc locations](https://github.com/aimingoo/ngx_cc#locations-in-nginxconf)

2. standard init.lua
> @see: $(ngx_4c)/init.lua

3. put webapp_demo.lua to $(ngx_4c)/scripts

```lua
-- /scripts/webapp_demo.lua
t.onRequestBegin = function(uri, method, arg)
	if uri == '/test' then
		local atPerWorker, r_ok, r_resps = route.isInvokeAtPer();
		if atPerWorker then
			ngx.say('hi, work at ', ngx.worker.pid())
		else
			ngx_cc.say(r_ok, r_resps)
		end
	end)
end
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

# N4C standard interfaces
@see $(ngx_4c)/ngx_4c.lua
```json
n4c = {
	-- for ngx_cc
	configuration = {
		default_channel_name = 'N4C',	-- channel name of ngx_cc
		max_buffered_length = 4096,		-- for n4c cached repsponse body
	},
	super = DEFAULT_CONIFG_SUPER,		-- default is 127.0.0.1:80

	-- n4c worker launcher
	startWorker = function() .. end,

	-- event loop
	doRequestBegin = function(uri, method, params) .. end,
	doBodyFilter = function(chunk, eof) .. end,
	doResponseEnd = function() .. end,
	doSessionClose = function() .. end,
	
	-- utilities or helper
	stat = function() .. end,  -- return a stat object
	register = function(scriptObject) .. end, -- load scriptObject
}
```

# N4C core framework
the core framework include features:
- buffered response body
 - try 4k only, settings n4c.configuration.max_buffered_length
- ngx.ctx.get_resp_object() will try return JSON object
 - lazy decode, high performances
 - result is cached in current request/session/context
- implementation /channel_name/api?transferServer interface for ngx_cc

@see $(ngx_4c)/scripts/n4cCoreFramework.lua

# Customizable headers in ngx_cc, or sub-request for proxy_pass
when send sub-request in nginx.conf, you cant dynamic setting/update headers.

but, with ngx_4c, you can call ngx_cc to send a customizable headers to upstream by proxy_pass. the feature provided by "n4c.doRequestBegin(true)":
```conf
	location ~ ^/([^/]+)/cast {
		internal;

		## n4c core: cc_headers custom support
		rewrite_by_lua 'n4c.doRequestBegin(true);';
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
# more event handles
@see $(ngx_4c)/scripts/n4cStatusReport.lua
@see $(ngx_4c)/testcase/t_nginx_phases.lua