-- Copyright (c) 2015-2021 Greg Owen gowen@swynwyr.com
-- MIT License see LICENSE

--[[
buildLookupTree function is used both to compile the configuration file
(conf2code.lua) and to update the tree on the fly to allow for CNAME 
mapping (dnSentry.lua)
]]

function buildLookupTree(tree, line)
	local fqdn = {}
	local word
	-- push each token of the fqdn onto the stack
	for word in string.gmatch(line:gsub("^%s*(.-)%s*$", "%1"), "[^.$]+") do
		table.insert(fqdn, word)
	end
	-- now pop them off to build the tree
	local last
	local tref
	local traf
	last = ""
	tref = tree
	traf = tree
	while (#fqdn > 0) do
		word = table.remove(fqdn)
		if word == "=" or word == "?" or word == "*" then
			traf[last] = word
			last = ""
			tref = tree
		elseif type(tref[word]) == "table" then
			tref = tref[word]
			last = word
		elseif tref[word] == nil then
			tref[word] = {}
			traf = tref
			tref = tref[word]
		else
			print(string.format("Parse error for %s at %s", line, type(tref[word])))
		end
		last = word
	end
end
