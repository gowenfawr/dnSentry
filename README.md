# dnSentry

`dnSentry` is an allowlist-based DNS firewall used to protect isolated servers from DNS-based data exfiltration and C2 traffic.


# Contents

 - [Why?](#why)
 - [Installation](#installation)
	 - [Prerequisites](#prerequisites)
	 - [File placement](#file-placement)
	 - [Create dnSentry configuration](#create-dnsentry-configuration)
	 - [Update PowerDNS Recursor configuration](#update-powerdns-recursor-configuration)
	 - [Restart PowerDNS Recursor](#restart-powerdns-recursor)
	 - [Test some queries](#test-some-queries)
 - [Logging](#logging)
 - [Known errors](#known-errors)
	 - [Empty domains.lua](#empty-domains.lua)
	 - [Novel $DIR](#novel-dir)

# <a name="why"></a>Why?

DNS exfiltration is one of the hardest routes to block.  Because DNS servers will pass requests out to the authoritative server, an attacker who sets up their own DNS server can arrange to get data handed to them.  That's why the infamous SUNBURST malware from the SolarWinds hack [used DNS](https://securelist.com/sunburst-connecting-the-dots-in-the-dns-requests/99862/) to vet initial compromises:

> In the initial phases, the Sunburst malware talks to the C&C server by sending encoded DNS requests. These requests contain information about the infected computer; if the attackers deem it interesting enough, the DNS response includes a CNAME record pointing to a second level C&C server.

Traditional blocklisting DNS firewalls like RPZ assume that traffic is good unless it's specifically blocked.  But it's impossible to proactively block all bad domains, especially if a bad actor is willing to set up a new domain solely to use against you.

The alternative - an allowlist based DNS firewall - is impractical for, say, user workstations, where web browsing will generate requests for an endless variety of DNS domains.  But protected servers, which are already isolated onto secure networks by traditional firewalls, have less need for random DNS activity.  The number of domains they need to query is small and predictable.  Blocking DNS activity by default will increase their security without cost to functionality.

# <a name="installation"></a>Installation
## <a name="prerequisites"></a>Prerequisites

dnSentry requires:
 - [PowerDNS Recursor](https://repo.powerdns.com/) 4.2+
 - Lua 5.1+

## <a name="file-placement"></a>File placement

The dnSentry files need to be placed under the configuration directory for PowerDNS Recursor.  On Debian/Ubuntu systems, this is `/etc/powerdns`.  On RHEL/CentOS/Fedora systems, this is `/etc/pdns-recursor`.  Whichever `$DIR` your system uses, create `$DIR/dnSentry` and copy the files there.

    root@dnsserver:/etc/powerdns/dnSentry# ls
    conf2code.lua  dnSentry.lua  domains.lua  LICENSE
    dnSentry.conf  dnTree.lua    dumper.lua   README.md

## <a name="create-dnsentry-configuration"></a>Create dnSentry configuration

Edit `$DIR/dnSentry/dnSentry.conf`, which will look like this:

    # Config file format
    # is a comment
    # All other lines are name tokens
    #       name token beginning with = means exact host match
    #       name token beginning with ? means all hosts under domain
    #       name token beginning with * means recursive hosts+subdomains
    =.docs.fastly.com
    ?.google.com
    *.microsoft.com
    *.10.in-addr.arpa

Add any internal domains, or any external partner domains, that are necessary for the server to function normally.  Once you've edited the file, use `lua` to run the `conf2code.lua` file which will generate the configuration.  Once you're satisfied, use `conf2code.lua` to overwrite `domains.lua` with the new configuration:

    root@dnsserver:/etc/powerdns/dnSentry# lua conf2code.lua
    tree = {
      arpa={ ["in-addr"]={ ["10"]="*" } },
      com={ fastly={ docs="=" }, google="?", microsoft="*" }
    }
    root@dnsserver:/etc/powerdns/dnSentry# lua conf2code.lua > domains.lua
    root@dnsserver:/etc/powerdns/dnSentry#


## <a name="update-powerdns-recursor-configuration"></a>Update PowerDNS Recursor configuration

Now edit the `$DIR/recursor.conf` file and specify that PowerDNS should run the `dnSentry.lua` script by it's full path:

    #################################
    # lua-dns-script        Filename containing an optional 'lua' script that will be used to modify dns answers
    #
    lua-dns-script=/etc/powerdns/dnSentry/dnSentry.lua

By default, PowerDNS Recursor will listen to localhost (127.0.0.1).  If you're only testing locally, you would put `nameserver 127.0.0.1` in `/etc/resolv.conf` to force testing, or you can specify the server used when testing with `host`/`nslookup`/`dig`.  

dnSentry protects best as a secure resolver for other machines, however, and in that case you need to listen to a public interface.  That setting `local-address` is also in the `recursor.conf` file; set it to your IP address.

    #################################
    # local-address IP addresses to listen on, separated by spaces or commas. Also accepts ports.
    #
    local-address=10.10.1.15

Then on any machines that you're protecting with dnSentry, update `/etc/resolv.conf` to point at this server, e.g., `nameserver 10.10.1.15` in this example.


## <a name="restart-powerdns-recursor"></a>Restart PowerDNS Recursor

    root@dnsserver:/etc/powerdns# systemctl restart pdns-recursor.service
    root@dnsserver:/etc/powerdns# tail -1 /var/log/syslog
    Aug  9 23:25:27 dnsserver pdns_recursor[2277]: Loaded 'lua' script from '/etc/powerdns/dnSentry/dnSentry.lua'

## <a name="test-some-queries"></a>Test some queries

Given the example config file, you should be able to query the following servers successfully, but all other domains should fail to resolve.

    root@dnsserver:~# host -t a docs.fastly.com
    docs.fastly.com is an alias for docs.fastly.com.map.fastly.net.
    docs.fastly.com.map.fastly.net has address 199.232.37.91
    root@dnsserver:~# host -t a www.google.com
    www.google.com has address 142.250.80.36
    root@dnsserver:~# host -t a www.catalog.update.microsoft.com
    www.catalog.update.microsoft.com is an alias for www.catalogupdate.microsoft.com.nsatc.net.
    www.catalogupdate.microsoft.com.nsatc.net has address 52.184.220.82
    root@dnsserver:~# host -t a cnn.com
    Host cnn.com not found: 3(NXDOMAIN)
    
If you want to test without changing the system resolver in `/etc/resolv.conf`, you can specify the server to query using `host`/`nslookup`/`dig`:

    root@dnsserver:~# host www.google.com localhost
    ...
    root@dnsserver:~# nslookup www.google.com localhost
    ...
    root@dnsserver:~# dig www.google.com @localhost

# <a name="logging"></a>Logging

Here is what `dnSentry` logged for those test queries:

    root@dnsserver:~# tail -4 /var/log/syslog
    Aug  9 23:32:15 dnsserver pdns_recursor[2682]: dnSentry=ALLOW client=127.0.0.1 name=docs.fastly.com. match=host qtype=1
    Aug  9 23:32:29 dnsserver pdns_recursor[2682]: dnSentry=ALLOW client=127.0.0.1 name=www.google.com. match=domain qtype=1
    Aug  9 23:32:35 dnsserver pdns_recursor[2682]: dnSentry=ALLOW client=127.0.0.1 name=www.catalog.update.microsoft.com. match=wildcard qtype=1
    Aug  9 23:32:42 dnsserver pdns_recursor[2682]: dnSentry=BLOCK client=127.0.0.1 name=cnn.com. qtype=1
    root@dnsserver:~#

Monitoring the logs and alerting on BLOCK messages acts both as an early detector that a malicious party is on your server, and as a way to ensure that legitimate functionality isn't being blocked by mistake.  Take the time to review these alerts to keep everything running smoothly.  Most production machines are very limited and predictable in their DNS activity, so alerts will hopefully be rare and valuable.

# <a name="known-errors"></a>Known Errors

## <a name="empty-domains.lua"></a>Empty domains.lua
If the `domains.lua` file is empty, the logs will contain errors that say `attempt to index local 'tref' (a nil value)`.  I recommend running `lua conf2code.lua` without output redirection first, to ensure it is outputting lua code, before using it to overwrite `domains.lua`.

    Aug  9 23:39:26 dnsserver pdns_recursor[3174]: STL error (cnn.com/A from 127.0.0.1:57824): [string "chunk"]:27: attempt to index local 'tref' (a nil value)
    Aug  9 23:39:32 dnsserver pdns_recursor[3174]: STL error (cnn.com/A from 127.0.0.1:57824): [string "chunk"]:27: attempt to index local 'tref' (a nil value)

## <a name="novel-dir"></a>Novel $DIR

If you install `dnSentry` in a `$DIR` other than the usual `/etc/powerdns` and `/etc/pdns-recursor`, PowerDNS Recursor startup will fail, complaining about `#011no file`.

    Aug  9 23:51:12 dnsserver systemd[1]: Started PowerDNS Recursor.
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: Done priming cache with root hints
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: Enabled 'epoll' multiplexer
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: Failed to load 'lua' script from '/etc/pdns/dnSentry/dnSentry.lua': [string "chunk"]:7: module 'domains' not found:
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no field package.preload['domains']
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file './domains.lua'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/usr/share/luajit-2.1.0-beta3/domains.lua'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/usr/local/share/lua/5.1/domains.lua'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/usr/local/share/lua/5.1/domains/init.lua'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/usr/share/lua/5.1/domains.lua'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/usr/share/lua/5.1/domains/init.lua'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/etc/powerdns/dnSentry/domains.lua'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/etc/pdns-recursor/dnSentry/domains.lua'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file './domains.so'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/usr/local/lib/lua/5.1/domains.so'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/usr/lib/x86_64-linux-gnu/lua/5.1/domains.so'
    Aug  9 23:51:12 dnsserver pdns_recursor[6094]: #011no file '/usr/local/lib/lua/5.1/loadall.so'
    Aug  9 23:51:12 dnsserver systemd[1]: pdns-recursor.service: Main process exited, code=exited, status=99/n/a
    Aug  9 23:51:12 dnsserver systemd[1]: pdns-recursor.service: Failed with result 'exit-code'.

If you must install dnSentry in a non-standard location, to avoid this error you need to edit line 6 of `dnSentry.lua` and ensure that the novel `$DIR` location is in the search path.
