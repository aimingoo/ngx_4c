-- mix/copy fields from ref to self
--	*) code from tundrawolf/lib/Distributed.lua
local function mix(self, ref, expanded)
	if ref == nil then return self end

	if type(ref) == 'function' then return expanded and ref or nil end
	if type(ref) ~= 'table' then return ref end

	self = (type(self) == 'table') and self or {}
	for key, value in pairs(ref) do
		self[key] = mix(self[key], value, expanded)
	end
	return self
end

return {
	mix = mix
}