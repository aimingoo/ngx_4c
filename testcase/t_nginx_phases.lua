--[[ testcase:
--	> curl 'http://localhost/t/exit_and_http_ok'
--	> curl 'http://localhost/t/exit_and_ngx_ok'
--]]

local t = {
	version = '2.0.0',
	scope = 'workers', -- root/clients/workers/root:workers
	desc = '测试：nginx phases checker'
}

local function log(...)
	ngx.log(ngx.ALERT, ...)
end

function t.doInternalRequestBegin()
	log('doInternalRequestBegin')
end

function t.doInternalResponseEnd()
	log('doInternalResponseEnd')
end

function t.doInternalSessionClose()
	log('doInternalSessionClose')
end

function t.doRequestBegin(uri, method, arg)
	log('doRequestBegin')

	if (uri == '/t/exit_and_http_ok') then
		ngx.exit(ngx.HTTP_OK)
	end

	if (uri == '/t/exit_and_ngx_ok') then
		ngx.exit(ngx.OK)
	end
end

function t.doResponseEnd()
	log('doResponseEnd')
end

function t.doSessionClose()
	log('doSessionClose')
end

return t