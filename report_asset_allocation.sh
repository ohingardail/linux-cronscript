#!/bin/bash
####################################################
# Project : https://github.com/ohingardail/linux-cronscript
# Author  : Adam Harrington
# Date    : 20 August 2014
# Licence : none (free for general use)
####################################################

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

echo '<html>'
echo "1. By asset class"
mysql --html --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<-EOF | sed 's/&lt;/</g;s/&gt;/>/g;s/\&amp;/\&/g'
call get_allocation(null, 'Asset class', now() );
EOF

echo "2. By asset region"
mysql --html --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<-EOF | sed 's/&lt;/</g;s/&gt;/>/g;s/\&amp;/\&/g'
call get_allocation(null, 'Location', now() );
EOF

echo '</html>'

