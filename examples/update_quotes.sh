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

# Get default currency
DEFAULT_CURRENCY=`mysql -s --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<EOF | sed 's/\t/,/g'
	select get_variable('Default currency');
EOF`

SQLOUTPUT=`mysql -s --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${GNUCASH_DATABASE} <<EOF | sed 's/\t/,/g'
	SELECT DISTINCT
		commodities.quote_source, 
		commodities.mnemonic as symbol
	FROM commodities
	WHERE quote_flag = 1
		AND commodities.mnemonic != '${DEFAULT_CURRENCY}'
	;
EOF`

# echo "SQLOUT: ${SQLOUTPUT}"

for ROW in `echo ${SQLOUTPUT}`
do
	#echo "ROW: ${ROW}"

	QUOTE_SOURCE=`echo "${ROW}" | cut -d, -f1`
	SYMBOL=`echo "${ROW}" | cut -d, -f2`

	QUOTE=""
	if [ "${QUOTE_SOURCE}" != "currency" ]
	then
		QUOTE=`/usr/bin/gnc-fq-dump ${QUOTE_SOURCE} ${SYMBOL} | sed 's/  */ /g;s/^ *//'`
		DATE=`echo "${QUOTE}" | grep '^date:' | cut -d' ' -f2`
		CURRENCY=`echo "${QUOTE}" | grep '^currency:' | cut -d' ' -f2`
		PRICE=`echo "${QUOTE}" | grep '^last:' | cut -d' ' -f2`
	else
		QUOTE=`/usr/bin/gnc-fq-dump currency ${SYMBOL} ${DEFAULT_CURRENCY}`
		DATE=`date +"%m/%d/%Y"`
		PRICE=`echo "${QUOTE}" | cut -d' ' -f4`
		CURRENCY=${DEFAULT_CURRENCY}
	fi

	# echo	"call post_commodity_price('${SYMBOL}', '${DATE}', '${CURRENCY}', '${PRICE}', 'Finance::Quote');"

	mysql -s --user=${GNUCASH_USERNAME} --password=${GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<-EOF
		call post_commodity_price('${SYMBOL}', '${DATE}', '${CURRENCY}', ${PRICE}, 'Finance::Quote');
	EOF

done
