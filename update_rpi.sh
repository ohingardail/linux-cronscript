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

# Download RPI file
wget -q -O- "http://www.ons.gov.uk/ons/datasets-and-tables/downloads/csv.csv?dataset=mm23&cdid=CZEQ" | egrep "^\"[0-9]{4} [A-Z]{3}\"," | sed 's/\"//g' |  sort -t" " -k 1n -k 2M > /tmp/rpi.csv
FILESIZE=`du -b /tmp/rpi.csv 2>/dev/null | cut -f1`

# Bail if RPI file is empty
if [ "${FILESIZE}" == "" -o "${FILESIZE}" == "0" ]
then
	exit 1
fi 

# Get previous value
SQLOUTPUT=`mysql -s --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<EOF | sed 's/\t/,/g'
	select 
		get_commodity_value(get_commodity_guid('XXX'), null) as "value",
		date_format(get_commodity_latest_date(get_commodity_guid('XXX')), "%Y%m%d") as "date";
EOF`

VALUE=`echo "${SQLOUTPUT}" | cut -d, -f1`
PREVIOUS_DATE=`echo "${SQLOUTPUT}" | cut -d, -f2`

# Wind through RPI file
cat /tmp/rpi.csv | while read LINE
do
	DATE=`echo "${LINE}" | cut -d, -f1 | sed 's/\([0-9]\{4\}\) \([A-Z]\{3\}\)/\2 \1/; s/^/15 /'`
	DATE=`date -d "${DATE}" +"%Y%m%d"`  # convert to sortable integer

	#echo DATE:${DATE}	
	#echo PREVIOUS_DATE:${PREVIOUS_DATE}

	if [ ${DATE} -gt ${PREVIOUS_DATE} ]
	then
		PERCENTAGE=`echo ${LINE} | cut -d, -f2`
		VALUE=`echo "scale=5; ${VALUE} + (${VALUE} * (${PERCENTAGE}/100))" | bc`
		DATE=`date -d "${DATE}" +"%m/%d/%Y"` # convert to gnc-fq-update form understood by add_commodity_price
		
		mysql -s --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<-EOF
			call post_commodity_price('XXX', '${DATE}', 'GBP', ${VALUE}, 'http://www.ons.gov.uk/ons/datasets-and-tables/downloads/csv.csv?dataset=mm23&cdid=CZEQ');
		EOF

	fi
done
