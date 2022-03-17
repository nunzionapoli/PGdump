#!/usr/bin/env bash

####################################################################################
####################################################################################
###
####       Author: Nunzio Napolitano
####       Version 1.0
###
####################################################################################
####################################################################################

CONFIGFILE=/etc/database_dump/settings.conf
source $CONFIGFILE
CREDENTIALS="--defaults-file=$CREDENTIAL_FILE"


DATE_FORMAT='%Y%m%d'
CURRENT_DATE=$(date +"${DATE_FORMAT}")
CURRENT_TIME=$(date +"%H%M")
LOGFILENAME=$LOG_PATH/database_dump-${CURRENT_DATE}-${CURRENT_TIME}.log

#SETUP DIRECTORY AND FILEMANE
dirDaily=$LOCAL_BACKUP_DIR/daily
dirMonthly=$LOCAL_BACKUP_DIR/monthly
dirYearly=$LOCAL_BACKUP_DIR/yearly
filenameDaily=backup-$(date +%Y-%m-%d)
filenameMonthly=backup-$(date +%Y-%m)
filenameYearly=backup-$(date +%Y)
sqlfile=$dirDaily/$filenameDaily.sql
zipfile=$dirDaily/$filenameDaily.zip
logfile=$LOCAL_BACKUP_DIR/history.log
# Make sure directories exists
mkdir -p $dirDaily
mkdir -p $dirMonthly
mkdir -p $dirYearly




[ ! -d $LOG_PATH ] && ${MKDIR} -p ${LOG_PATH}
echo "" > ${LOGFILENAME}
echo "<<<<<<   Database Dump Report :: `date +%D`  >>>>>>" >> ${LOGFILENAME}
echo "" >> ${LOGFILENAME}
echo "DB Name  :: DB Size   Filename" >> ${LOGFILENAME}

### Make a backup ###
check_config(){
	### Check if configuration file exists.
        [ ! -f $CONFIGFILE ] && close_on_error "Config file not found, make sure config file is correct"
}
mysqldb_backup(){

	### Start database backups
        if [ "$DB_NAMES" == "ALL" ]; then
		DATABASES=`$MYSQL $CREDENTIALS -h $MYSQL_HOST -P $MYSQL_PORT -Bse 'show databases' | grep -Ev "^(Database|mysql|performance_schema|information_schema)"$`
        else
		DATABASES=$DB_NAMES
        fi

        db=""
        [ ! -d $BACKUPDIR ] && ${MKDIR} -p $BACKUPDIR
                [ $VERBOSE -eq 1 ] && echo "*** Dumping MySQL Database ***"
                mkdir -p ${LOCAL_BACKUP_DIR}/${CURRENT_DATE}
        for db in $DATABASES
        do
                FILE_NAME="${db}.${filenameDaily}.sql.gz"
                FILENAMEPATH="$dirDaily$FILE_NAME"
                [ $VERBOSE -eq 1 ] && echo -en "Database> $db... \n"
                ${MYSQLDUMP} ${CREDENTIALS} --single-transaction -h ${MYSQL_HOST} -P $MYSQL_PORT $db | ${GZIP} -9 > $FILENAMEPATH
                echo "$db   :: `du -sh ${FILENAMEPATH}`"  >> ${LOGFILENAME}
                [ $FTP_ENABLE -eq 1 ] && ftp_backup
                [ $SFTP_ENABLE -eq 1 ] && sftp_backup
                [ $S3_ENABLE -eq 1 ] && s3_backup
        done
        [ $VERBOSE -eq 1 ] && echo "*** Backup completed ***"
        [ $VERBOSE -eq 1 ] && echo "*** Check backup files in ${FILE_PATH} ***"
}


pgdb_backup(){

	### Start database backups
 	DATABASES=$DB_NAMES
 
        db=""
        for db in $DATABASES
        do
                FILE_NAME="${db}.${filenameDaily}"
                FILENAMEPATH="$dirDaily$FILE_NAME"
                [ $VERBOSE -eq 1 ] && echo -en "Database> $db... \n"

                ${PGDUMP} --host ${PG_HOST} --username $user --format=custom --file ${FILENAMEPATH} --dbname={db}

                errorDuringBackup=""
                if [ $? == 0 ]; then
                        # Update monthly/yearly backups
                        cp $FILENAMEPATH $dirMonthly/$db_$filenameMonthly.dmp
                        cp $FILENAMEPATH $dirYearly/$db_$filenameYearly.dmp
                else
                errorDuringBackup='pg_dump returned non-zero code'
                fi
                echo "$db   :: `du -sh ${FILENAMEPATH}`"  >> ${LOGFILENAME}
                [ $FTP_ENABLE -eq 1 ] && ftp_backup
                [ $SFTP_ENABLE -eq 1 ] && sftp_backup
                [ $S3_ENABLE -eq 1 ] && s3_backup

        done
        [ $VERBOSE -eq 1 ] && echo "*** Backup completed ***"
        [ $VERBOSE -eq 1 ] && echo "*** Check backup files in ${FILE_PATH} ***"
}

### close_on_error on demand with message ###
close_on_error(){
        echo "$@"
        exit 99
}

### Make sure bins exists.. else close_on_error
check_cmds(){
        [ ! -x $GZIP ] && close_on_error "FILENAME $GZIP does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $RM ] && close_on_error "FILENAME $RM does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $MKDIR ] && close_on_error "FILENAME $MKDIR does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $GREP ] && close_on_error "FILENAME $GREP does not exists. Make sure correct path is set in $CONFIGFILE."
	if [ $S3_ENABLE -eq 1 ]; then
	       [ ! -x $S3CMD ] && close_on_error "FILENAME $S3CMD does not exists. Make sure correct path is set in $CONFIGFILE."
	fi
	if [ $SFTP_ENABLE -eq 1 ]; then
		[ ! -x $SCP ] && close_on_error "FILENAME $SCP does not exists. Make sure correct path is set in $CONFIGFILE."
	fi
	if [ $DB_TYPE -eq "MYSQL" ]; then
        [ ! -x $MYSQL ] && close_on_error "FILENAME $MYSQL does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $MYSQLDUMP ] && close_on_error "FILENAME $MYSQLDUMP does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $MYSQLCHECK ] && close_on_error "FILENAME $MYSQLCHECK does not exists. Make sure correct path is set in $CONFIGFILE."
	fi
	if [ $DB_TYPE -eq "PGSQL" ]; then
        [ ! -x $PSQL ] && close_on_error "FILENAME $PSQL does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $PGDUMP ] && close_on_error "FILENAME $PGDUMP does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $PGCHECK ] && close_on_error "FILENAME $PGCHECK does not exists. Make sure correct path is set in $CONFIGFILE."
	fi

}

### Check if database connectin is working...
check_mysql_connection(){
        ${MYSQLCHECK} ${CREDENTIALS} -h ${MYSQL_HOST} -P ${MYSQL_PORT} ping | ${GREP} 'alive'>/dev/null
        [ $? -eq 0 ] || close_on_error "Error: Cannot connect to MySQL Server. Make sure username and password setup correctly in $CONFIGFILE"
}

check_postgres_connection(){
        ${PGSQLCHECK}  -h ${PG_HOST} -p ${PG_PORT}
        [ $? -eq 0 ] || close_on_error "Error: Cannot connect to Postgresql Server. Make sure username and password setup correctly in $CONFIGFILE"
}


### Copy backup files to ftp server
ftp_backup(){
[ $VERBOSE -eq 1 ] && echo "Uploading backup file to FTP"
ftp -n $FTP_SERVER << EndFTP
user "$FTP_USERNAME" "$FTP_PASSWORD"
binary
hash
cd $FTP_UPLOAD_DIR
lcd $dirDaily
put "$FILE_NAME"
bye
EndFTP
}

### Copy backup files to sftp server
sftp_backup(){

	[ $VERBOSE -eq 1 ] && echo "Uploading backup file to SFTP"
	cd ${dirDaily}
	${SCP} -P ${SFTP_PORT}  "$FILE_NAME" ${SFTP_USERNAME}@${SFTP_HOST}:${SFTP_UPLOAD_DIR}/

}

### Copy backup files to Amazon S3 bucket
s3_backup(){
	[ $VERBOSE -eq 1 ] && echo "Uploading backup file to S3 Bucket"
	cd ${dirDaily}
	$S3CMD --access_key="$AWS_ACCESS_KEY" --secret_key="$AWS_SECRET_ACCESS_KEY" put "$FILE_NAME" s3://${S3_BUCKET_NAME}/${S3_UPLOAD_LOCATION}/
}

### Remove older backups
clean_old_backups(){

	[ $VERBOSE -eq 1 ] && echo "Removing old backups"
	DBDELDATE=`date +"${DATE_FORMAT}" --date="${BACKUP_RETAIN_DAYS} days ago"`
	if [ ! -z ${LOCAL_BACKUP_DIR} ]; then
		  cd ${LOCAL_BACKUP_DIR}
		  if [ ! -z ${DBDELDATE} ] && [ -d ${DBDELDATE} ]; then
				rm -rf ${DBDELDATE}
		  fi
	fi
}

### Send report email
send_report(){
	if [ $SENDEMAIL -eq 1 ]
	then
			cat ${LOGFILENAME} | mail -vs "Database dump report for `date +%D`" ${EMAILTO}
	fi
}



### main ####
check_config
check_cmds
if [ $DB_TYPE -eq "MYSQL" ]; then
        #check_mysql_connection
        #mysqldb_backup
fi
if [ $DB_TYPE -eq "PGSQL" ]; then
        #check_pgsql_connection
        #pgdb_backup
fi
#clean_old_backups
send_report
