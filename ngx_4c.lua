-----------------------------------------------------------------------------
-- NGX_4C v0.9.0
-- Author: aimingoo@wandoujia.com
-- Copyright (c) 2015.05
-- Descition:　n4c programming architecture, the Controllable, Computable and Communication Cluster in nginx.
--
-- Usage:
--	n4c = require('ngx_4c').apply(n4c, events)
--
-- the module initiating n4c standard interfaces
-----------------------------------------------------------------------------
return {
	apply = function(framework, events)
		local function is_n4c_request()
			-- @see: http://wiki.nginx.org/HttpLuaModule#ngx.var.VARIABLE
			local saved_uri = ngx.var.saved_uri
			return ngx.re.match(saved_uri == "" and ngx.var.uri or saved_uri or "",
				'^/[^/]+/(cast|invoke|hub)', 'o') ~= nil
		end

		local internal_doRequestBegin = function(is_n4c_casting)
			if is_n4c_casting and ngx.ctx.cc_headers then  -- process cc_headers
				-- note: get_headers() will get inherited headers before proxy_pass set/reset
				-- 		 but, these headers is update and valid: 'Content-Length'
				local has_custom_headers = type(ngx.ctx.cc_headers) == 'table'
				if (ngx.ctx.cc_headers == 'OFF') or has_custom_headers then
					local headers = ngx.req.get_headers()
					for name in pairs(headers) do ngx.req.clear_header(name) end
					if has_custom_headers then -- will copy headers
						for name, value in pairs(ngx.ctx.cc_headers) do ngx.req.set_header(name, value) end
					else -- will use default headers in ngx_4c
						ngx.req.set_header('User-Agent', 'n4c/1.0.0')
						ngx.req.set_header('Accept', '*/*')
						ngx.req.set_header('Content-Type', 'text/plain; charset=UTF-8')
					end
					ngx.req.set_header('Content-Length', headers['Content-Length'] or '')
				end
			elseif not ngx.is_subrequest then
				events[is_n4c_request() and "InternalRequestBegin" or "RequestBegin"](
					ngx.var.uri, ngx.var.request_method, ngx.req.get_uri_args());
			end
		end

		local counter = {cast=0, subrequest=0, request=0}
		local stat_doRequestBegin = function(is_n4c_casting)
			if is_n4c_casting then counter.cast = counter.cast + 1 end
			if ngx.is_subrequest then
				counter.subrequest = counter.subrequest + 1
			else
				counter.request = counter.request + 1
			end
			internal_doRequestBegin(is_n4c_casting)
		end

		-- or, change to internal_doRequestBegin()
		framework.doRequestBegin = stat_doRequestBegin

		framework.doBodyFilter = function()
			-- When setting nil or an empty Lua string value to ngx.arg[1], no data chunk will be passed to the downstream Nginx output filters at all.
			--	(need check length of arg, and validate arg[1])

			-- !!!dont access #ngx.arg or unpack it, there are invalid!!!
			if not ngx.is_subrequest then
				local BodyFilter, ResponseEnd = "BodyFilter", "ResponseEnd"
				if is_n4c_request() then
					BodyFilter, ResponseEnd = "InternalBodyFilter", "InternalResponseEnd"
				end

				if ngx.arg[1] then	-- has body data
					events[BodyFilter](ngx.arg[1], ngx.arg[2])
				end

				if ngx.arg[2] then  -- is <eof>
					events[ResponseEnd](ngx.var.uri, ngx.ctx.ContentLength or 0, ngx.ctx.buffered)
				end
			end
		end

		framework.doSessionClose = function()
			-- enter session close, when all handles is done in  onResponseEnd event.
			--	*) cant use coroutine in log_by_lua, maybe you need clean something in body_filter phase
			if not ngx.is_subrequest then
				events[is_n4c_request() and "InternalSessionClose" or "SessionClose"](ngx.var.uri, ngx.ctx)
			end
		end

		-- Utils: status report
		framework.stat = function() return counter end

		-- Utils: simple script register
		framework.register = function(scriptObject)
			for key, value, prefix in pairs(scriptObject) do
				prefix = key:sub(1, 2)
				if prefix == 'do' then -- ignore prefix
					events.on(key:sub(3), value)
				end
			end
		end

		return framework
	end
}