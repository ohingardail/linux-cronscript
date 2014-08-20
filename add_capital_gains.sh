#!/bin/bash

# load parmfiles if exist
if [ -d ../parms ]
then
for PARMFILE in `find ../parms -type f -executable -user ${USER} | sort`
do 
	if [ "${DEBUG}" == "ON" ]
	then
		${ECHO} "Loading parameter file : ${PARMFILE}"
	fi
	
	. ${PARMFILE}
done
fi

# check that mysql is running
if [ `systemctl show mysqld.service | grep SubState= | awk -F= '{print $NF}'` != 'running' ]
then
	exit 1
fi

# add required capital gains or losses 
mysql -s --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<-EOF 
call post_all_gains();
EOF
