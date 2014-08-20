#!/bin/bash
####################################################
# Project : https://github.com/ohingardail/linux-cronscript
# Author : Adam Harrington
# Date : 20 August 2014
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

# Year parameters
THISYEAR=`date +'%Y'`
THISMONTH=`date +'%m'`
LASTYEAR=`echo ${THISYEAR} - 1 | bc`
LASTMONTH=`echo ${THISMONTH} -1 | bc`
if [ ${LASTMONTH} -lt 1 ]
then
	LASTMONTH=`echo 12 - ${LASTMONTH} | bc`
fi

# Download file
wget -q -O- "http://landregistry.data.gov.uk/app/hpi/hpi_data.csv?from_m=${LASTMONTH}&from_y=${LASTYEAR}&loc_0=Reading&loc_uri_0=http%3A%2F%2Flandregistry.data.gov.uk%2Fid%2Fregion%2Freading&m_apt=t&m_hpi=1&source=preview_form&to_m=${LASTMONTH}&to_y=${THISYEAR}" | egrep "^\"[JFMASOND][a-z]{2,8} [0-9]{4}\""| sed 's/\"//g' | sort -t" " -k 2n -k 1M  > /tmp/house_prices.csv
FILESIZE=`du -b /tmp/house_prices.csv 2>/dev/null | cut -f1`

# Bail if file is empty
if [ "${FILESIZE}" == "" -o "${FILESIZE}" == "0" ]
then
	exit 1
fi 

# Get previous value
SQLOUTPUT=`mysql -s --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<EOF | sed 's/\t/,/g'
	select 
		get_commodity_value(get_commodity_guid('XHS'), null) as "value",
		date_format(get_commodity_latest_date(get_commodity_guid('XHS')), "%Y%m%d") as "date";
EOF`

PREVIOUS_VALUE=`echo "${SQLOUTPUT}" | cut -d, -f1`
PREVIOUS_DATE=`echo "${SQLOUTPUT}" | cut -d, -f2`

# Wind through file
cat /tmp/house_prices.csv | while read LINE
do
	DATE=`echo "${LINE}" | cut -d, -f1 | sed 's/^/15 /'`
	DATE=`date -d "${DATE}" +"%Y%m%d"`  # convert to sortable integer

	#echo DATE:${DATE}	
	#echo PREVIOUS_DATE:${PREVIOUS_DATE}

	if [ ${DATE} -gt ${PREVIOUS_DATE} ]
	then

		VALUE=`echo "${LINE}" | awk -F, '{print $NF}'`
		SOURCE=`echo "${LINE}" | cut -d, -f4 | sed 's/\"//g'`
		DATE=`date -d "${DATE}" +"%m/%d/%Y"` # convert to gnc-fq-update form understood by add_commodity_price
		
		#echo "call post_commodity_price('XHS', ${DATE}, 'GBP', ${VALUE}, '${SOURCE}');"
		mysql -s --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<-EOF
			call post_commodity_price('XHS', '${DATE}', 'GBP', ${VALUE}, '${SOURCE}');	
		EOF
	fi
done
