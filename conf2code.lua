-- Copyright (c) 2015-2021 Greg Owen gowen@swynwyr.com
-- MIT License see LICENSE

--[[
conf2code.lua reads the dnSentry.conf configuration file and outputs a
lua code snippet.  The dnSentry.lua code then reads that snippet in as 
configuration, usually from a file named domains.lua.
]]

require("dumper")
require("dnTree")

tree = {}

io.input("dnSentry.conf")
while true do 
	local line = io.read()
	if line == nil then break end
	if string.find(line, "#") == nil then
		buildLookupTree(tree, line)
	end
end
text = DataDumper(tree)
text = string.gsub(text, "^return", "tree =")
print(text)
