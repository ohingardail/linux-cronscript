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

# check required binaries
MYSQL=`which mysql 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'mysql' command."
	exit
fi

# Set and initialise SQL command file
SQL_COMMANDS=/tmp/custom_indices.$$.sql

echo "delimiter //"  							> ${SQL_COMMANDS}

echo "drop procedure if exists load_new_indices;" 			>> ${SQL_COMMANDS}
echo "//" 								>> ${SQL_COMMANDS}

echo "create procedure load_new_indices()" 				>> ${SQL_COMMANDS}
echo "begin" 								>> ${SQL_COMMANDS}
echo "declare l_err_code		char(5) default '00000';" 	>> ${SQL_COMMANDS}
echo "declare l_err_msg			text;"				>> ${SQL_COMMANDS}
echo "declare l_inflation_index_guid	varchar(32);"			>> ${SQL_COMMANDS}
echo "declare l_house_price_index_guid	varchar(32);"			>> ${SQL_COMMANDS}
echo "declare continue handler for SQLEXCEPTION" 			>> ${SQL_COMMANDS}
echo "begin" 								>> ${SQL_COMMANDS}
echo "get diagnostics condition 1" 					>> ${SQL_COMMANDS}
echo "l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;" 	>> ${SQL_COMMANDS}
echo "call log(concat('ERROR : [', l_err_code , '] : load_new_indices : ', l_err_msg ));"						>> ${SQL_COMMANDS}
echo "end;" 																>> ${SQL_COMMANDS}

echo "if not exists_commodity( get_variable( 'Inflation index') ) then" 								>> ${SQL_COMMANDS}
echo "do post_commodity( get_variable( 'Inflation index' ), 'CURRENCY', 'Inflation index', '000', null, null, null, null );" 		>> ${SQL_COMMANDS}
echo "end if;" 																>> ${SQL_COMMANDS}
echo "if not exists_commodity( get_variable( 'House price index') ) then" 								>> ${SQL_COMMANDS}
echo "do post_commodity( get_variable( 'House price index' ), 'CURRENCY', 'House price index', '000', null, null, null, null );" 	>> ${SQL_COMMANDS}
echo "end if;" 																>> ${SQL_COMMANDS}

# 1. Update specified inflation index

# Download file containing requried inflation data (UK GBP RPI data, in this case)
SOURCE="http://www.ons.gov.uk/ons/datasets-and-tables/downloads/csv.csv?dataset=mm23&cdid=CZEQ"
wget -q -O- "${SOURCE}" | egrep "^\"[0-9]{4} [A-Z]{3}\"," | sed 's/\"//g' |  sort -t" " -k 1n -k 2M > /tmp/rpi.csv

if [ -s /tmp/rpi.csv ]
then

	# Get previous value
	SQLOUTPUT=`mysql -s --user=${CUSTOM_GNUCASH_USERNAME} --password=${CUSTOM_GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<-EOF | sed 's/\t/,/g'
	select 
		get_commodity_price(get_commodity_guid(get_variable( 'Inflation index')), get_commodity_latest_date(get_commodity_guid(get_variable( 'Inflation index'))) ) as "value",
		date_format(get_commodity_latest_date(get_commodity_guid(get_variable( 'Inflation index'))), "%Y%m%d") as "date";
	EOF`

	VALUE=`echo "${SQLOUTPUT}" | cut -d, -f1`
	PREVIOUS_DATE=`echo "${SQLOUTPUT}" | cut -d, -f2`
	
	COUNT_LOOPS=1
	while read LINE
	do
		VALUE_DATE=`echo "${LINE}" | cut -d, -f1 | sed 's/\([0-9]\{4\}\) \([A-Z]\{3\}\)/\2 \1/; s/^/15 /'`
		VALUE_DATE=`date -d "${VALUE_DATE}" +"%Y%m%d"`  # convert to sortable integer
		
		if [ ${VALUE_DATE} -gt ${PREVIOUS_DATE} ]
		then
			PERCENTAGE=`echo ${LINE} | cut -d, -f2`
			VALUE=`echo "scale=5; ${VALUE} + (${VALUE} * (${PERCENTAGE}/100))" | bc`
		
			if [ ${COUNT_LOOPS} -eq 1 ] 
			then
				echo "call post_commodity_attribute( get_commodity_guid( get_variable( 'Inflation index' ) ),'method', str_to_date('${VALUE_DATE}', '%Y%m%d'), '${SOURCE}'); " >> ${SQL_COMMANDS}
				echo "call post_commodity_attribute( get_commodity_guid( get_variable( 'Inflation index' ) ),'currency', str_to_date('${VALUE_DATE}', '%Y%m%d'), get_variable('Default currency') ); " >> ${SQL_COMMANDS}
			fi

			echo "call post_commodity_attribute( get_commodity_guid( get_variable( 'Inflation index' ) ),'price', str_to_date('${VALUE_DATE}', '%Y%m%d'), '${VALUE}'); " >> ${SQL_COMMANDS}

			COUNT_QUOTES=$(( ${COUNT_QUOTES:-0} + 1 ))
			COUNT_LOOPS=$(( ${COUNT_LOOPS} + 1 ))
		fi

	done < <( cat /tmp/rpi.csv )
fi

# 2. Update specified house price index

# Download file containing requried inflation data (UK GBP RPI data, in this case)

SOURCE="http://landregistry.data.gov.uk/app/hpi/hpi_data.csv?from_m=0&from_y=1999&loc_0=Reading&loc_uri_0=http%3A%2F%2Flandregistry.data.gov.uk%2Fid%2Fregion%2Freading&m_apt=t&m_hpi=1&source=preview_form&to_m=$(( `date +'%m'` -1 ))&to_y=`date +'%Y'`"
wget -q -O- "${SOURCE}" | egrep "^\"[JFMASOND][a-z]{2,8} [0-9]{4}\""| sed 's/\"//g' | sort -t" " -k 2n -k 1M  > /tmp/house_prices.csv

if [ -s /tmp/house_prices.csv ]
then

	# Get previous value
	SQLOUTPUT=`mysql -s --user=${CUSTOM_GNUCASH_USERNAME} --password=${CUSTOM_GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<-EOF | sed 's/\t/,/g'
	select 
		get_commodity_price(get_commodity_guid(get_variable( 'House price index')), get_commodity_latest_date(get_commodity_guid(get_variable( 'House price index')))) as "value",
		date_format(get_commodity_latest_date(get_commodity_guid(get_variable( 'House price index'))), "%Y%m%d") as "date";
	EOF`

	VALUE=`echo "${SQLOUTPUT}" | cut -d, -f1`
	PREVIOUS_DATE=`echo "${SQLOUTPUT}" | cut -d, -f2`
	
	COUNT_LOOPS=1
	while read LINE
	do
		VALUE_DATE=`echo "${LINE}" | cut -d, -f1 | sed 's/^/15 /'`
		VALUE_DATE=`date -d "${VALUE_DATE}" +"%Y%m%d"`  # convert to sortable integer
		
		if [ ${VALUE_DATE} -gt ${PREVIOUS_DATE} ]
		then
			VALUE=`echo "${LINE}" | awk -F, '{print $NF}'`
		
			if [ ${COUNT_LOOPS} -eq 1 ] 
			then
				echo "call post_commodity_attribute( get_commodity_guid( get_variable( 'House price index' ) ),'method', str_to_date('${VALUE_DATE}', '%Y%m%d'), '${SOURCE}'); " >> ${SQL_COMMANDS}
				echo "call post_commodity_attribute( get_commodity_guid( get_variable( 'House price index' ) ),'currency', str_to_date('${VALUE_DATE}', '%Y%m%d'), get_variable('Default currency') ); " >> ${SQL_COMMANDS}
			fi

			echo "call post_commodity_attribute( get_commodity_guid( get_variable( 'House price index' ) ),'price', str_to_date('${VALUE_DATE}', '%Y%m%d'), '${VALUE}'); " >> ${SQL_COMMANDS}

			COUNT_QUOTES=$(( ${COUNT_QUOTES:-0} + 1 ))
			COUNT_LOOPS=$(( ${COUNT_LOOPS} + 1 ))
		fi

	done < <( cat /tmp/house_prices.csv )
fi

echo "end;" >> ${SQL_COMMANDS}
echo "//" >> ${SQL_COMMANDS}

echo "call load_new_indices();" >> ${SQL_COMMANDS}
echo "//" >> ${SQL_COMMANDS}

echo "drop procedure load_new_indices;" >> ${SQL_COMMANDS}
echo "//" >> ${SQL_COMMANDS}

echo "commit;" >> ${SQL_COMMANDS}
echo "//" >> ${SQL_COMMANDS}

# execute the SQL script generated to load index values into customgnucash database 
if [ -s ${SQL_COMMANDS} -a ${COUNT_QUOTES} -gt 0 ]
then
	${MYSQL} -As --user=${CUSTOM_GNUCASH_USERNAME} --password=${CUSTOM_GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} < ${SQL_COMMANDS}
fi
if [ -f ${SQL_COMMANDS} ]
then
	rm -f ${SQL_COMMANDS}
fi
