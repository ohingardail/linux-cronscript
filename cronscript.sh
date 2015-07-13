#!/bin/bash
####################################################
# Project : https://github.com/ohingardail/linux-cronscript
# Author  : Adam Harrington
# Date    : 13 July 2015
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
CP=`which cp 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'cp' command."
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
HEAD=`which head 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'head' command."
	exit
fi
WC=`which wc 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'wc' command."
	exit
fi
TR=`which tr 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'tr' command."
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
TOUCH=`which touch 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'touch' command."
fi
BASENAME=`which basename 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'basename' command."
fi
DU=`which du 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'du' command."
	exit
fi
PS=`which ps 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'ps' command."
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

for FOLDER in parms temp mail once prepared ${MODE}
do
	if [ ! -d ${FOLDER} -a ! -f ${FOLDER} ]
	then 
		if [ "${DEBUG}" == "ON" ]
		then
			${ECHO} "Making folder : ${FOLDER}"
		fi
		mkdir ${FOLDER}
	fi
done

# load parmfiles if exist
for PARMFILE in `${FIND} parms -type f -executable | ${EGREP} -v "(${ME}|~)" | ${SORT}`
do 
	if [ "${DEBUG}" == "ON" ]
	then
		${ECHO} "Loading parameter file : ${PARMFILE}"
	fi
	
	. ${PARMFILE}
done

# install inbound custom instructions, if any
if [ "${USER}" != "root" -a -d "${NOTIFICATION_IN_FOLDER}" ]
then
	for NOTIFICATION_FILE in `${FIND} ${NOTIFICATION_IN_FOLDER} -type f -user ${USER} -name "do*" | ${EGREP} -v "(${ME}|~)" | ${SORT}`
	do 
		EXECFILE=`${BASENAME} ${NOTIFICATION_FILE}`
		if [ -O prepared/${EXECFILE} ]
		then
			${CP} prepared/${EXECFILE} once/${EXECFILE}
			${CHMOD} 744 once/${EXECFILE}
			${RM} ${NOTIFICATION_FILE}
		fi
	done
fi

# clean up old datafiles
${FIND} . -mtime +${KEEP_OLD:=7} -type f -user ${USER} -name "*.notified" -delete
# ${FIND} . -mtime +${KEEP_OLD:=7} -type f -user ${USER} -name "*.done" -delete
# ${FIND} . -mtime +1 -type f -user ${USER} -name "*.running" -delete	
if [ -d "${NOTIFICATION_OUT_FOLDER}" ]
then
	${FIND} ${NOTIFICATION_OUT_FOLDER} -mtime +${KEEP_OLD:=7} -type f -user ${USER} -delete
fi

# cycle through files to run
ITERATION=0
if [ "${MODE}" != "" -a `echo "${MODE}" | egrep -c '^(parms|mail|prepepared|temp)$'` -eq 0 ]
then
	
	for EXECFILE in `${FIND} ${MODE} -type f -executable -user ${USER} | ${EGREP} -v "(${ME}|~|\.done$)" | ${SORT}`
	do 
	
		ITERATION=$(( ${ITERATION} + 1 ))
		if [ "${DEBUG}" == "ON" ]
		then
			${ECHO} "Mode ${MODE} : Iteration ${ITERATION} : ${EXECFILE}"
		fi
		
		LOGFILE="mail/`${BASENAME} ${EXECFILE} | ${AWK} -F. '{print $1}'`.`${ECHO} ${MODE} | ${SED} 's/^\.\///' | ${AWK} -F\/ '{print $1}'`.`date +'%Y%m%d%H%M%S'`".$$
		
		# if file is executable and is not already being executed ...
		# if [ -x ${EXECFILE} -a `${PS} -efl | ${GREP} -v grep | ${GREP} "${EXECFILE}" | ${WC} -l` -eq 0 ]
		if [ -x ${EXECFILE} -a ! -f ${EXECFILE}.running  ]
		then

			# show task has started	
			${TOUCH} ${EXECFILE}.running
		
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
			#bash ${EXECFILE} >> ${LOGFILE}.log
			${EXECFILE} >> ${LOGFILE}.log
					
			# mark 'once' jobs as unreadable for next time around
			if [ "${MODE}" == "once" ]
			then
				${CHMOD} 000 ${EXECFILE}
				mv ${EXECFILE} ${EXECFILE}.$$
			fi

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

				${RM} ${EXECFILE}.running
			fi
	
		else
			${ECHO} "Can't find executable script ${EXECFILE}, or it is already running."
			exit
		fi
		
	done

# notify user of results
elif [ "${MODE}" == "mail" ]
then
	
	# loop through all completed output files "*.completed"
	for MAILFILE in `${FIND} ${MODE} -type f -user ${USER} -name "*.completed"`
	do
		ITERATION=$(( ${ITERATION} + 1 ))
		
		if [ "${DEBUG}" == "ON" ]
		then
			${ECHO} "Mode ${MODE} : Iteration ${ITERATION} : ${MAILFILE}"
		fi
		
		FILEBASE=`${BASENAME} -s ".completed" "${MAILFILE}"`
		JOBNAME=`${BASENAME} "${MAILFILE}" | ${AWK} -F. '{print $1"."$2}'`
		FILETYPE=`${FILE} -bi "${MAILFILE}" | ${AWK} -F\; '{print $1}'`
			
		# File too big - do not send, but notify user of location (if not already done so)
		if [ "`${DU} -b ${MAILFILE} | ${AWK} '{print $1}'`" -gt ${MAXSIZE} ]
		then
			${ECHO} -e "Cron job output file is `${DU} -k ${MAILFILE} | ${AWK} '{print $1}'` kb in size and is too big to email.\nFile is stored on source machine ${HOSTNAME} at ${PWD}/${MAILFILE}." | ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} "Scheduled job : ${JOBNAME}" ${EMAILTO}
			RETURNCODE=$?

		# Nothing to send (filesize is 0, or all lines contain only whitespace or control chars)
		elif [ "`${DU} -b ${MAILFILE} | ${AWK} '{print $1}'`" -eq 0 -o "`${CAT} ${MAILFILE} | ${SED} '/^[[:space:][:cntrl:]]*$/d' | ${WC} -m`" -eq 0 ]
		then
			${RM} -f ${MAILFILE}
			RETURNCODE=$?
		
		# Send file as attachment if > 50kB or is a non-text file
		elif [ "`${DU} -b ${MAILFILE} | ${AWK} '{print $1}'`" -gt $((1024 * 50 )) -o `${ECHO} ${FILETYPE} | ${GREP} -c '^text'` -eq 0 ]
		then
			# remove '.completed' suffix in attached file
			${CP} ${MAILFILE} ./temp/${FILEBASE}

			${ECHO} "Cron job attachment ${HOSTNAME}:${FILEBASE}." | ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} "Scheduled job : ${JOBNAME}" ${ATTACHPARM} ./temp/${FILEBASE} ${EMAILTO}
			RETURNCODE=$?

			${RM} ./temp/${FILEBASE}

		# send reasonably sized text output as email or notification
		else 

			# Extract out customised JOBNAME line (if any)
			CUSTOM_JOBNAME=`${GREP} '^TITLE:' ${MAILFILE} | ${HEAD} -1 | ${AWK} -F'TITLE:' '{print $NF}'`
			if [ "${CUSTOM_JOBNAME}" != "" ]
			then
				# subject padded to 64+ chars, because (at least one instance of) hierloom mailx puts a newline after the subject line if its 52-64 chars long, causing "\nContent-Type" to appear after *2* newlines and resulting in a badly formatted email
				SUBJECT=`printf '%-65s' "Scheduled job : ${CUSTOM_JOBNAME}" | ${SED} 's/[[:cntrl:]]//g'`
			else
				SUBJECT="Scheduled job : ${JOBNAME}"
			fi

			# send as HTML email
			if [ `${ECHO} "${MAILFILE}" | ${GREP} -c "\.html\."` -gt 0 ]
			then
				${SED} 's/^TITLE://; /^[[:space:][:cntrl:]]*$/d' ${MAILFILE} | ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} "$( ${ECHO} -e "${SUBJECT}\nContent-Type: text/html" )" ${EMAILTO}
				RETURNCODE=$?
			
			# send as iOS notification (using IFTTT via dropbox) if its not HTML and very small and the appropriate notification folder exists
			elif [ "`${DU} -b ${MAILFILE} | ${AWK} '{print $1}'`" -le 250 -a -d "${NOTIFICATION_OUT_FOLDER}" ]
			then
				${TOUCH} "${NOTIFICATION_OUT_FOLDER}/`${CAT} ${MAILFILE}`"
				RETURNCODE=$?

			# last resort : send as plaintext email
			else
				${SED} 's/^TITLE://; /^[[:space:][:cntrl:]]*$/d' ${MAILFILE} | ${MAIL} ${FROMPARM} ${EMAILFROM} ${SUBJECTPARM} "${SUBJECT}" ${EMAILTO}
				RETURNCODE=$?

			fi # if [ `${ECHO} "${MAILFILE}" | ${GREP} -c "\.html\."` -gt 0 ]

		fi # if [ "`${DU} -b ${MAILFILE} | ${AWK} '{print $1}'`" -gt ${MAXSIZE} ]

		# Manage remaining output file
		if [ -f ${MAILFILE} ]
		then
			if [ ${RETURNCODE} -eq 0 ]
			then
				${MV} ${MAILFILE} ${MAILFILE}.notified
			else
				${MV} ${MAILFILE} ${MAILFILE}.err
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
