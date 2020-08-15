#!/bin/bash

source /usr/local/etc/kismet_sql.conf

# /usr/local/bin/kismet -s --daemonize >/dev/null 2>&1
systemctl start kismet
while true ; do
#	if ! ps ax |grep -v grep |grep "kismet -s --daemonize" >/dev/null ; then
#		/usr/local/bin/kismet -s --daemonize >/dev/null 2>&1
i#	fi	

	if ! ps ax |grep -v grep |grep "kismet_sql.py" >/dev/null ; then
		/usr/local/bin/kismet_sql.py --database $database &>/dev/null 2>&1
	fi	
	sleep 10s
done
