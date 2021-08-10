-- Copyright (c) 2015-2021 Greg Owen gowen@swynwyr.com
-- MIT License see LICENSE
-- Version 0.9.0

-- Import the lua code version of the configuration
package.path = package.path..";/etc/powerdns/dnSentry/?.lua;/etc/pdns-recursor/dnSentry/?.lua"
require("domains")
require("dnTree")

function preresolve ( name )
	local fqdn = {}
	local word
	local lname, remoteip, qtype
	lname = tostring(name.qname)
	remoteip = name.remoteaddr
	qtype = name.qtype
	-- push each token of the fqdn onto the stack
	for word in string.gmatch(lname, "([^%.]+)%.") do
		table.insert(fqdn, word)
	end
	-- now pop them off to walk the tree
	local tref
	tref = tree
	local message
	while (#fqdn > 0) do
		word = table.remove(fqdn)
		if tref[word] == nil then
			pdnslog(string.format("dnSentry=BLOCK client=%s name=%s qtype=%s", remoteip, lname, qtype))
			name.rcode = pdns.NXDOMAIN
			return true;
		elseif type(tref[word]) == "table" then
			tref = tref[word]
		elseif type(tref[word]) == "string" then
			if tref[word] == "=" and #fqdn == 0 then
				pdnslog(string.format("dnSentry=ALLOW client=%s name=%s match=host qtype=%s", remoteip, lname, qtype))
				return false;
			elseif tref[word] == "?" and #fqdn <= 1 then
				pdnslog(string.format("dnSentry=ALLOW client=%s name=%s match=domain qtype=%s", remoteip, lname, qtype))
				return false;
			elseif tref[word] == "*" then
				pdnslog(string.format("dnSentry=ALLOW client=%s name=%s match=wildcard qtype=%s", remoteip, lname, qtype))
				return false;
			end
			pdnslog(string.format("dnSentry=BLOCK client=%s name=%s fallthrough=%s qtype=%s", remoteip, lname, tref[word], qtype))
			name.rcode = pdns.NXDOMAIN
			return true;
		end
	end
	pdnslog(string.format("dnSentry=BLOCK name=%s fallthrough=\"Exhausted Tree\" qtype=%s", lname, qtype))
	name.rcode = pdns.NXDOMAIN
	return true;
end


