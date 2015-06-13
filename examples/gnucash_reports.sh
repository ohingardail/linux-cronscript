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
if [ `systemctl show mysql.service | grep ActiveState= | awk -F= '{print $NF}'` != 'active' ]
then
	exit 1
fi

# get all reports (actually 100, but it seems unlikely one would have that many)
mysql -A --batch --raw --skip-column-names --user=${CUSTOM_GNUCASH_USERNAME} --password=${CUSTOM_GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<-EOF 
	call get_report(100);
EOF
