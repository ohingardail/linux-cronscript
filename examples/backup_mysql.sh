#!/bin/bash
####################################################
# Project : https://github.com/ohingardail/linux-cronscript
# Author : Adam Harrington
# Date : 20 August 2014
# Licence : none (free for general use)
####################################################

# check that required binaries can be found

MYSQLDUMP=`which mysqldump 2>/dev/null`
if [ $? -ne 0 ]
then
        echo "Unable to find 'mysqldump' command."
        exit 1
fi

MYSQL=`which mysql 2>/dev/null`
if [ $? -ne 0 ]
then
        echo "Unable to find 'mysql' command."
        exit 1
fi

BZIP2=`which bzip2 2>/dev/null`
if [ $? -ne 0 ]
then
	echo "Unable to find 'bzip2'."
	exit 1
fi

# check that required output folder is available
if [ ! -d ${BACKUP_OUTPUT} ]
then
        mkdir ${BACKUP_OUTPUT}
        if [ $? -ne 0 ]
        then
                echo "Unable to create ${BACKUP_OUTPUT}"
                exit 1
        fi
fi

# check that mysql is running
if [ `systemctl show mysqld.service | grep SubState= | awk -F= '{print $NF}'` != 'running' ]
then
	exit 1
fi

# check that mysql access is possible
echo exit | ${MYSQL} --user=${DBUSER} --password=${DBPASSWORD}
if [ $? -ne 0 ]
then
        echo "Unable to connect to local MySQL instance."
        exit 1
fi

MACHINENAME=`uname -n`
DATESTAMP=`date +"%Y%m%d%H%M%S"`

# backup mysql DB
${MYSQLDUMP} --all-databases --user=${DBUSER} --password=${DBPASSWORD} | ${BZIP2} --best > ${BACKUP_OUTPUT}/mysqldump.${MACHINENAME}.${DATESTAMP}.sql.bz2
if [ $? -ne 0 ]
then
        echo "MySQL backup failed."
        exit 1
fi

# make file readable only by owner
chmod 700 ${BACKUP_OUTPUT}/mysqldump.${MACHINENAME}.${DATESTAMP}.sql.bz2

# weed out old backups
find ${BACKUP_OUTPUT} -type f -name "mysqldump.${MACHINENAME}.*.sql.bz2" -ctime +${BACKUP_KEEP} -delete 
if [ $? -ne 0 ]
then
	echo "Unable to delete old backups."
	exit 1
fi
