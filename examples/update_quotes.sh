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

# check required binaries
MYSQL=`which mysql 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'mysql' command."
	exit
fi
GNC_FQ_DUMP=`which gnc-fq-dump 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'gnc-fq-dump' command."
	exit
fi
WGET=`which wget 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'wget' command."
	exit
fi
GREP=`which grep 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'grep' command."
	exit
fi
EGREP=`which egrep 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'egrep' command."
	exit
fi
AWK=`which awk 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'awk' command."
	exit
fi
SED=`which sed 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'sed' command."
	exit
fi
CUT=`which cut 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'cut' command."
	exit
fi
SORT=`which sort 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'sort' command."
	exit
fi

# check that mysql is running
if [ `systemctl show mysql.service | ${GREP} ActiveState= | ${AWK} -F= '{print $NF}'` != 'active' ]
then
	exit 1
fi

# Set command file
SQL_COMMANDS=/tmp/quotes.$$.sql

# Get a list of commodities to enquire for
SQLOUTPUT=`${MYSQL} -s --user=${CUSTOM_GNUCASH_USERNAME} --password=${CUSTOM_GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} <<EOF | ${SED} 's/\t/,/g'
	SELECT DISTINCT
		commodities.quote_source, 
		commodities.mnemonic,
		commodities.guid,
		ifnull(min(price.value_date), current_date ),
		ifnull(min(divs.value_date), current_date ),
		ifnull(max(divs.value_date), date_add(current_date, interval -10 year)),
		get_variable( concat('Historical price data for ', commodities.mnemonic )),
		get_variable('Default currency')
	FROM commodities
		LEFT OUTER JOIN commodity_attribute divs 
			ON commodities.guid = divs.commodity_guid
			AND divs.field = 'div'
		LEFT OUTER JOIN commodity_attribute price 
			ON commodities.guid = price.commodity_guid
			AND price.field = 'price'
	WHERE quote_flag = 1
		AND commodities.mnemonic != get_variable('Default currency')
	GROUP BY
		commodities.quote_source, 
		commodities.mnemonic,
		commodities.guid,
		get_variable( concat('Historical price data for ', commodities.mnemonic )),
		get_variable('Default currency');
EOF`

# echo "${SQLOUTPUT}"
# exit

# Ask Finance:quote for details for each commodity
echo "${SQLOUTPUT}" | while read ROW
do
	QUOTE_SOURCE=`echo "${ROW}" | ${CUT} -d, -f1`
	COMMODITY_SYMBOL=`echo "${ROW}" | ${CUT} -d, -f2`
	COMMODITY_GUID=`echo "${ROW}" | ${CUT} -d, -f3`
	EARLIEST_PRICE=`echo "${ROW}" | ${CUT} -d, -f4`
	EARLIEST_DIV=`echo "${ROW}" | ${CUT} -d, -f5`
	LATEST_DIV=`echo "${ROW}" | ${CUT} -d, -f6`
	HISTORICAL_PRICE_STATUS=`echo "${ROW}" | ${CUT} -d, -f7`
	DEFAULT_CURRENCY=`echo "${ROW}" | ${CUT} -d, -f8`

	EARLIEST_QUOTE_DATE=`date +"%Y%m%d"`
	COUNT_QUOTES=0

	unset DUMP_OUTPUT
	unset QUOTE_VALUE
	declare -Axg QUOTE_VALUE

	# needs to be a procedure if "if" statements and in a block if exception handlers are being used
	echo "delimiter //"  							> ${SQL_COMMANDS}

	echo "drop procedure if exists load_new_prices;" 			>> ${SQL_COMMANDS}
	echo "//"								>> ${SQL_COMMANDS}

	echo "create procedure load_new_prices()" 				>> ${SQL_COMMANDS}
	echo "begin"								>> ${SQL_COMMANDS}
	echo "declare l_err_code	char(5) default '00000';" 		>> ${SQL_COMMANDS}
	echo "declare l_err_msg		text;" 					>> ${SQL_COMMANDS}
	echo "declare continue handler for SQLEXCEPTION" 			>> ${SQL_COMMANDS}
	echo "begin" 								>> ${SQL_COMMANDS}
	echo "get diagnostics condition 1" 					>> ${SQL_COMMANDS}
	echo "l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;" 	>> ${SQL_COMMANDS}
	echo "call log(concat('ERROR : [', l_err_code , '] : load_new_prices [${COMMODITY_SYMBOL}] : ', l_err_msg ));" >> ${SQL_COMMANDS}
	echo "end;" 								>> ${SQL_COMMANDS}

	# For commodities that aren't currencies...
	if [ "${QUOTE_SOURCE}" != "currency" ]
	then

		# only load historical data once
		if [ `echo "${HISTORICAL_PRICE_STATUS}" | ${GREP} -c '^Loaded'` -eq 0 ]
		then
			# Ask Yahoo Finance directly for historical share prices
			${WGET} -qO /tmp/${COMMODITY_SYMBOL}.prices "http://real-chart.finance.yahoo.com/table.csv?s=${COMMODITY_SYMBOL}&a=0&b=1&c=2000&d=$((`date +%m` - 1))&e=`date +%d`&f=`date +%Y`&g=d&ignore=.csv"

			if [ -s /tmp/${COMMODITY_SYMBOL}.prices ]
			then
		
				COUNT_LOOP=1
				while read LINE
				do
					VALUE_DATE=`echo ${LINE}  | ${AWK} -F, '{print $1}'`
					VALUE=`echo ${LINE} | ${AWK} -F, '{print $5}'`

					# load the historical price up to the earliest quote already in the DB
					if [ `date --date="${VALUE_DATE}" +"%Y%m%d"` -lt `date --date="${EARLIEST_PRICE}" +"%Y%m%d"` ]
					then
						if [ ${COUNT_LOOP} -eq 1 ] 
						then
							echo "call post_commodity_attribute('${COMMODITY_GUID}','method', str_to_date('${VALUE_DATE}', '%Y-%m-%d'), 'Yahoo Finance CSV'); " >> ${SQL_COMMANDS}
							echo "call post_commodity_attribute('${COMMODITY_GUID}','currency', str_to_date('${VALUE_DATE}', '%Y-%m-%d'), get_commodity_mnemonic(get_commodity_currency('${COMMODITY_GUID}')) ); " >> ${SQL_COMMANDS}
						fi

						echo "call post_commodity_attribute('${COMMODITY_GUID}','price', str_to_date('${VALUE_DATE}', '%Y-%m-%d'), '${VALUE}'); " >> ${SQL_COMMANDS}

						COUNT_QUOTES=$(( ${COUNT_QUOTES} + 1 ))

						# keep a tally of the earliest date for which a quote was added
						if [ `date --date="${VALUE_DATE}" +"%Y%m%d"` -lt `date --date="${EARLIEST_QUOTE_DATE}" +"%Y%m%d"` ]
						then
							EARLIEST_QUOTE_DATE=${VALUE_DATE}
						fi
					fi
					COUNT_LOOP=$(( ${COUNT_LOOP} + 1 ))
				done < <(sort -t, -k1,1 -u /tmp/${COMMODITY_SYMBOL}.prices | ${EGREP} '^[0-9]{4}')

				# log that historical data has been loaded, if any have been loaded
				if [ ${COUNT_QUOTES} -gt 0 ]
				then
					echo "call delete_variable('Historical price data for ${COMMODITY_SYMBOL}'); " >> ${SQL_COMMANDS}
					echo "call post_variable('Historical price data for ${COMMODITY_SYMBOL}', 'Loaded ${COUNT_QUOTES} values'); " >> ${SQL_COMMANDS}
				fi

			fi # if [ -s /tmp/${COMMODITY_SYMBOL}.prices ]		

		fi # if [ "${COMMODITY_HISTORICAL_PRICE_STATUS}" != "Loaded" ]
		
		# Ask Yahoo:Finance directly for historical dividend details
		${WGET} -qO /tmp/${COMMODITY_SYMBOL}.divs "http://real-chart.finance.yahoo.com/table.csv?s=${COMMODITY_SYMBOL}&a=0&b=1&c=2000&d=$((`date +%m` - 1))&e=`date +%d`&f=`date +%Y`&g=v&ignore=.csv"

		if [ -s /tmp/${COMMODITY_SYMBOL}.divs ]
		then
			while read LINE
			do
				VALUE_DATE=`echo ${LINE}  | ${AWK} -F, '{print $1}'`
				VALUE=`echo ${LINE} | ${AWK} -F, '{print $2}'`

				# load dividend data [1] up to the earliest div already in the DB and [2] after the latest date in the DB
				if [ `date --date="${VALUE_DATE}" +"%Y%m%d"` -lt `date --date="${EARLIEST_DIV}" +"%Y%m%d"` -o `date --date="${VALUE_DATE}" +"%Y%m%d"` -gt `date --date="${LATEST_DIV}" +"%Y%m%d"` ]
				then
					echo "call post_commodity_attribute('${COMMODITY_GUID}','div', str_to_date('${VALUE_DATE}', '%Y-%m-%d'), '${VALUE}'); " >> ${SQL_COMMANDS}
					COUNT_QUOTES=$(( ${COUNT_QUOTES} + 1 ))
				fi				
			done < <(${SORT} -t, -k1,1 -u /tmp/${COMMODITY_SYMBOL}.divs | ${EGREP} '^[0-9]{4}')

		fi # if [ -s /tmp/${COMMODITY_SYMBOL}.divs ]

		# Remove working files
		rm -f /tmp/${COMMODITY_SYMBOL}.prices
		rm -f /tmp/${COMMODITY_SYMBOL}.divs

		# extract other (today's) values from Finance::Quote
		DUMP_OUTPUT=`${GNC_FQ_DUMP} -v ${QUOTE_SOURCE} ${COMMODITY_SYMBOL} 2>/dev/null | ${GREP} "^${COMMODITY_SYMBOL}" | ${SED} "s/^${COMMODITY_SYMBOL}//; s/^ *//; s/: /:/"`

		if [ "${DUMP_OUTPUT}" != "" ]
		then
			# load values into associative array
			while read LINE
			do
				VAR=`echo "${LINE}" | cut -d: -f1`
				VAL=`echo "${LINE}" | cut -d: -f2`
				
				# only load useful values (div values returned by gnc-fq-dump seem to be v poor quality)
				if [ "${VAL}" != "" -a `echo "${VAR}" | ${EGREP} -c '(errormsg|name|symbol|success|div)'` -eq 0 ]
				then
					QUOTE_VALUE[${VAR}]="${VAL}"
				fi
			done < <(echo "${DUMP_OUTPUT}")

			# calculate price date
			if [ "${QUOTE_VALUE[price]}" != "" ] 
			then
				if [ "${QUOTE_VALUE[isodate]}" != "" ] 
				then
					PRICE_DATE="${QUOTE_VALUE[isodate]}"

				elif [ "${QUOTE_VALUE[date]}" != "" ]
				then
					PRICE_DATE=`echo "${QUOTE_VALUE[date]}" | ${AWK} -f/ '{print $3"-"$1"-"$2}'`

				else
					PRICE_DATE=`date +"%Y-%m-%d"`
				fi
			fi

			# calculate dividend date if required 
			# (code included for completeness - not used because gnc-fq-dump returns poor quality values) 
			if [ "${QUOTE_VALUE[div]}" != "" ] 
			then
				if [ "${QUOTE_VALUE[div_date]}" != "" ] 
				then
					DIV_DATE=`echo "${QUOTE_VALUE[div_date]}" | ${AWK} -f/ '{print $3"-"$1"-"$2}'`

				elif [ "${QUOTE_VALUE[ex_div]}" != "" ]
				then
					DIV_DATE=`date --date="${QUOTE_VALUE[ex_div]} +1 day" +"%Y-%m-%d"`

				else
					DIV_DATE="${PRICE_DATE}"
				fi

				# make sure dividend date is in the past (ex_div has no year component)
				if [ `date --date="${DIV_DATE}" +"%Y%m%d"` -gt `date +"%Y%m%d"` ]
				then
					DIV_DATE=`date -d "${DIV_DATE} -1 year" +"%Y-%m-%d"`
				fi 
			fi

			# create SQL commands to load values into custom gnucash
			for KEY in "${!QUOTE_VALUE[@]}"
			do
				# dont load date attributes from Finance:Quote
				if [ `echo "${KEY}" | ${GREP} -c 'date'` -eq 0 ]
				then
					# dividend values use a different date
					if [ "${KEY}" = "div" ] 
					then
						VALUE_DATE="${DIV_DATE}"
					else
						VALUE_DATE="${PRICE_DATE}"			
					fi

					if [ `echo "${QUOTE_VALUE[$KEY]}" | ${GREP} -ic "unknown"` -eq 0 ]
					then
						echo "call post_commodity_attribute('${COMMODITY_GUID}','${KEY}', str_to_date('${VALUE_DATE}', '%Y-%m-%d' ), '${QUOTE_VALUE[$KEY]}'); " >> ${SQL_COMMANDS}
						COUNT_QUOTES=$(( ${COUNT_QUOTES} + 1 ))
					fi

					# keep a tally of the earliest date for which a quote was added
					if [ `date --date="${VALUE_DATE}" +"%Y%m%d"` -lt `date --date="${EARLIEST_QUOTE_DATE}" +"%Y%m%d"` ]
					then
						EARLIEST_QUOTE_DATE=${VALUE_DATE}
					fi
				fi
			done
		fi

	else # if [ "${QUOTE_SOURCE}" != "currency" ]

		# load today's currency value
		DUMP_OUTPUT=`${GNC_FQ_DUMP} currency ${COMMODITY_SYMBOL} ${DEFAULT_CURRENCY} 2>/dev/null`

		if [ "${DUMP_OUTPUT}" != "" ]
		then
			VALUE=`echo "${DUMP_OUTPUT}" | ${CUT} -d' ' -f4`

			if [ `echo "${VALUE}" | ${GREP} -ic "unknown"` -eq 0 ]
			then
				echo "call post_commodity_attribute('${COMMODITY_GUID}','price', current_date, '${VALUE}'); " >> ${SQL_COMMANDS}
				COUNT_QUOTES=$(( ${COUNT_QUOTES} + 1 ))
			fi
		fi

	fi # if [ "${QUOTE_SOURCE}" != "currency" ]
	
	if [ "${EARLIEST_QUOTE_DATE}" != "" ]
	then
		echo "if not is_locked('commodity_attribute', 'WAIT') then" >> ${SQL_COMMANDS}
		echo "call delete_derived_commodity_attributes('${COMMODITY_GUID}', str_to_date('${EARLIEST_QUOTE_DATE}', '%Y-%m-%d'));" >> ${SQL_COMMANDS}
		echo "end if;" >> ${SQL_COMMANDS}
	fi

	echo "end;" >> ${SQL_COMMANDS}
	echo "//" >> ${SQL_COMMANDS}

	echo "call load_new_prices();" >> ${SQL_COMMANDS}
	echo "//" >> ${SQL_COMMANDS}

	echo "drop procedure load_new_prices;" >> ${SQL_COMMANDS}
	echo "//" >> ${SQL_COMMANDS}

	echo "commit;" >> ${SQL_COMMANDS}
	echo "//" >> ${SQL_COMMANDS}

	# exit

	# execute the SQL script generated to load quote values into customgnucash database 
	if [ -s ${SQL_COMMANDS} -a ${COUNT_QUOTES} -gt 0 ]
	then
		${MYSQL} -As --user=${CUSTOM_GNUCASH_USERNAME} --password=${CUSTOM_GNUCASH_PASSWORD} --database=${CUSTOM_GNUCASH_DATABASE} < ${SQL_COMMANDS}
	fi
	if [ -f ${SQL_COMMANDS} ]
	then
		rm -f ${SQL_COMMANDS}
	fi
done

