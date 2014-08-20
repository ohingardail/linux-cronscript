#!/bin/bash
####################################################
# Project : https://github.com/ohingardail/linux-cronscript
# Author  : Adam Harrington
# Date    : 20 August 2014
# Licence : none (free for general use)
####################################################

# Load profiles
for PROFILE in /etc/profile . ~/.bashrc
do
	if [ -f ${PROFILE} ]
	then
		if [ "${DEBUG}" == "ON" ]
		then
			echo "Loading : ${PROFILE}"
		fi
		. ${PROFILE}
	fi
done

# set local parameters
if [ "${DEBUG}" == "" ]
then
	DEBUG="OFF"
fi
ME=`basename ${0} | awk -F. '{print $1}'`
MODE="mail" # default mode
MAXSIZE=$(( 1024 * 1024))  # max size of file to email

# check commandline parms
while getopts r:d opt
do	
	case "${opt}" in
		r)	MODE="${OPTARG}";;
		d)	DEBUG="ON";;
		*)	MODE="mail";;
	esac
done

# find required binaries
MV=`which mv 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'mv' command."
	exit
fi
RM=`which rm 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'rm' command."
	exit
fi
ECHO=`which echo 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'echo' command."
	exit
fi
CAT=`which cat 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'cat' command."
	exit
fi
FIND=`which find 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'find' command."
	exit
fi
SORT=`which sort 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'sort' command."
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
CHMOD=`which chmod 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'chmod' command."
	exit
fi
FILE=`which file 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'file' command."
	exit
fi
DOS2UNIX=`which dos2unix 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'dos2unix' command."
fi
DU=`which du 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'du' command."
	exit
fi
MAIL=`which email 2>/dev/null`
if [ $? -ne 0 ]
then
	MAIL=`which mail 2>/dev/null`
	if [ $? -ne 0 ]
	then
		echo "Unable to find 'mail' or 'email' command."
		exit
	else
		# fedora 'mailx' parms
		# FROMPARM="-r"
		FROMPARM=""
		EMAILFROM=""		
		SUBJECTPARM="-s"
		ATTACHPARM="-a"
		HTMLPARM=""
	fi
else
	# cygwin 'email' parms
	FROMPARM="-f"
	SUBJECTPARM="-s"
	ATTACHPARM="--attach"
	HTMLPARM="--html"
fi

if [ "${DEBUG}" == "ON" ]
then
	echo "Starting : ${ME}"
	echo "Mode : ${MODE}"
fi

# set up local folder structure if not there
if [ ! -d ${HOME}/cron/ ]
then
	if [ "${DEBUG}" == "ON" ]
	then
		${ECHO} "Making folder : ${HOME}/cron/"
	fi
	mkdir ${HOME}/cron/
fi

cd ${HOME}/cron/

for FOLDER in parms temp mail ${MODE}
do
	if [ ! -d ${FOLDER} ]
	then 
		if [ "${DEBUG}" == "ON" ]
		then
			${ECHO} "Making folder : ${FOLDER}"
		fi
		mkdir ${FOLDER}
	fi
done

# load parmfiles if exist
for PARMFILE in `${FIND} parms -type f -executable -user ${USER} | ${EGREP} -v "(${ME}|~)" | ${SORT}`
do 
	if [ "${DEBUG}" == "ON" ]
	then
		${ECHO} "Loading parameter file : ${PARMFILE}"
	fi
	
	. ${PARMFILE}
done

# cycle through files to run
ITERATION=0
if [ "${MODE}" != "" -a "${MODE}" != "mail" ]
then
	
	for EXECFILE in `${FIND} ${MODE} -type f -executable -user ${USER} | ${EGREP} -v "(${ME}|~)" | ${SORT}`
	do 
	
		ITERATION=$(( ${ITERATION} + 1 ))
		if [ "${DEBUG}" == "ON" ]
		then
			${ECHO} "Mode ${MODE} : Iteration ${ITERATION} : ${EXECFILE}"
		fi
		
		LOGFILE="mail/`basename ${EXECFILE} | ${AWK} -F. '{print $1}'`.`${ECHO} ${MODE} | ${SED} 's/^\.\///' | ${AWK} -F\/ '{print $1}'`.`date +'%Y%m%d%H%M%S'`".$$
		#touch ${LOGFILE}.log
		
		# if file is executable and is not already being executed ...
		if [ -x ${EXECFILE} -a `ps -efl | grep -v grep | grep "${EXECFILE}" | wc -l` -eq 0 ]
		then
		
			if [ "${DEBUG}" == "ON" ]
			then
				${ECHO} "Mode ${MODE} : Executing : ${EXECFILE}"
			fi

			# Convert to unix format if you can			
			if [ "${DOS2UNIX}" != "" ]
			then			
				${DOS2UNIX} -q ${EXECFILE} 2>&1 >/dev/null		
			fi
	
			# Execute file
			bash ${EXECFILE} >> ${LOGFILE}.log
		
			# show task is completed
			if [ -f ${LOGFILE}.log ]
			then
				${CHMOD} 777 ${LOGFILE}.log
				if [ `${GREP} -c '<html>' ${LOGFILE}.log` -gt 0 ]
				then
					${MV} ${LOGFILE}.log ${LOGFILE}.html.completed
				else
					${MV} ${LOGFILE}.log ${LOGFILE}.log.completed
				fi			
			fi
			
			# mark 'once' jobs as unreadable for next time around
			if [ "${MODE}" == "once" ]
			then
				${CHMOD} 000 ${EXECFILE}
			fi
		else
			${ECHO} "Can't find executable script ${EXECFILE}, or it is already running."
			exit
		fi
		
		#if [ "${ITERATION}" -gt 10 ]
		#then
		#	break
		#else
		#	sleep ${ITERATION}
		#fi
	done

# mail results
elif [ "${MODE}" == "mail" ]
then

	# clean up old datafiles
	for OLDFILE in `${FIND} ${MODE} -mtime +3 -type f -user ${USER} -name "*.sent"`
	do
		if [ "${DEBUG}" == "ON" ]
		then
			${ECHO} "Removing old file : ${OLDFILE}"
		fi
	
		${RM} -f ${OLDFILE}	
	done

	for OLDFILE in `${FIND} ${MODE} -mtime +30 -type f -user ${USER} -name "*.notified"`
	do
		if [ "${DEBUG}" == "ON" ]
		then
			${ECHO} "Removing old file : ${OLDFILE}"
		fi

		${RM} -f ${OLDFILE}	
	done

	for MAILFILE in `${FIND} ${MODE} -type f -user ${USER} -name "*.completed"`
	do
		ITERATION=$(( ${ITERATION} + 1 ))
		
		if [ "${DEBUG}" == "ON" ]
		then
			${ECHO} "Mode ${MODE} : Iteration ${ITERATION} : ${MAILFILE}"
		fi
			
		JOBNAME=`basename ${MAILFILE} | ${AWK} -F. '{print $1"."$2}'`
		FILETYPE=`${FILE} -bi ${MAILFILE} | awk -F\; '{print $1}'`
			
		# File too big - do not send, but notify user of location (if not already done so)
		if [ "`${DU} -b ${MAILFILE} | ${AWK} '{print $1}'`" -gt ${MAXSIZE} ]
		then
			if [ `${ECHO} "${MAILFILE}" | ${GREP} -c "\.notified"` -eq 0 ]
			then
				${ECHO} -e "Cron job output file is `${DU} -k ${MAILFILE} | ${AWK} '{print $1}'` kb in size and is too big to email.\nFile is stored on source machine ${HOSTNAME} at ${PWD}/${MAILFILE}." | ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} "Scheduled job : ${JOBNAME}" ${EMAILTO}
				${MV} ${MAILFILE} ${MAILFILE}.notified
			fi

		# Nothing to send
		elif [ "`${DU} -b ${MAILFILE} | ${AWK} '{print $1}'`" -eq 0 ]
		then
			if [ `${ECHO} "${MAILFILE}" | ${GREP} -c "\.notified"` -eq 0 ]
			then
				#${ECHO} "Cron job output file ${HOSTNAME}:${MAILFILE} existed but had no content." | ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} "Scheduled job : ${JOBNAME}" ${EMAILTO}
				#${MV} ${MAILFILE} ${MAILFILE}.notified
				${RM} -f ${MAILFILE}
			fi
		
		# Send file as attachment if > 50kB or is a non-text file
		elif [ "`${DU} -b ${MAILFILE} | ${AWK} '{print $1}'`" -gt $((1024 * 50 )) -o `${ECHO} ${FILETYPE} | grep -c '^text'` -eq 0 ]
		then
			${ECHO} "Cron job attachment ${HOSTNAME}:${MAILFILE}." | ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} "Scheduled job : ${JOBNAME}" ${ATTACHPARM} ${MAILFILE} ${EMAILTO}
			if [ $? -eq 0 ]
			then
				${MV} ${MAILFILE} ${MAILFILE}.sent
			else
				${MV} ${MAILFILE} ${MAILFILE}.err
			fi
			
		# Send file inline
		else
			if [ `${ECHO} "${MAILFILE}" | ${GREP} -c "\.html\."` -gt 0 ]
			then
				if [ "${DEBUG}" == "ON" ]
				then
					echo "${CAT} ${MAILFILE} \| ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} \"$(${ECHO} -e \"Scheduled job : ${JOBNAME}\nContent-Type: text/html\")\" ${EMAILTO}"
				fi
				${CAT} ${MAILFILE} | ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} "$(${ECHO} -e "Scheduled job : ${JOBNAME}\nContent-Type: text/html")" ${EMAILTO}
			
				if [ $? -eq 0 ]
				then
					${MV} ${MAILFILE} ${MAILFILE}.sent
				else
					${MV} ${MAILFILE} ${MAILFILE}.err
				fi
			
			else
				if [ "${DEBUG}" == "ON" ]
				then
					echo "${SED} '/^[	 ]*$/d' ${MAILFILE} \| ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} \"Scheduled job : ${JOBNAME}\"  ${EMAILTO}"
				fi
				${SED} '/^[	 ]*$/d' ${MAILFILE} | ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} "Scheduled job : ${JOBNAME}"  ${EMAILTO}

				if [ $? -eq 0 ]
				then
					${MV} ${MAILFILE} ${MAILFILE}.sent
				else
					${MV} ${MAILFILE} ${MAILFILE}.err
				fi
			fi
		fi

		#if [ "${ITERATION}" -gt 10 ]
		#then
		#	break
		#else
		#	sleep ${ITERATION}
		#fi
		
	done
fi

if [ "${DEBUG}" == "ON" ]
then
	${ECHO} "Ending : ${ME}"
fi
