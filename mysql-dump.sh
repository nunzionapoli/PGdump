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
MYSQLCREDENTIAL="--defaults-file=$MYSQLCREDENTIAL_FILE"

###  SETUP DIRECTORY AND FILEMANE
dirDaily=$LOCAL_BACKUP_DIR/daily
dirMonthly=$LOCAL_BACKUP_DIR/monthly
dirYearly=$LOCAL_BACKUP_DIR/yearly
filenameDaily=bck-$(date +%Y-%m-%d)
filenameMonthly=bck-$(date +%Y-%m)
filenameYearly=bck-$(date +%Y)
logfile=$LOCAL_BACKUP_DIR/history.log
# Make sure directories exists
[ ! -d $LOCAL_BACKUP_DIR ] && mkdir -p $LOCAL_BACKUP_DIR
mkdir -p $dirDaily
mkdir -p $dirMonthly
mkdir -p $dirYearly

# IF not exist  heade di history, copialo
echo "" >> ${logfile}
echo "<<<<<<   Database Dump Report :: `date +%D`  >>>>>>" >> ${logfile}
echo "" >> ${logfile}
echo "DB Name  :: DB Size   Filename" >> ${logfile}


### Make a backup ###
mysqldb_backup(){

	### Start database backups
        if [ "$DB_NAMES" == "ALL" ]; then
		DATABASES=`$MYSQL $MYSQLCREDENTIAL -h $MYSQL_HOST -P $MYSQL_PORT -Bse 'show databases' | grep -Ev "^(Database|mysql|performance_schema|information_schema)"$`
        else
		DATABASES=$DB_NAMES
        fi

        db=""
        [ $VERBOSE -eq 1 ] && echo "*** Dumping MySQL Database ***"
        for db in $DATABASES
        do
                FILE_NAME="${db}_${filenameDaily}.sql.gz"
                FILENAMEPATH="$dirDaily$FILE_NAME"
                [ $VERBOSE -eq 1 ] && echo -en "Database> $db... \n"
 #               ${MYSQLDUMP} ${MYSQLCREDENTIAL} --single-transaction -h ${MYSQL_HOST} -P $MYSQL_PORT $db | ${GZIP} -9 > $FILENAMEPATH
                echo "$db   :: `du -sh ${FILENAMEPATH}`"  >> ${logfile}
                [ $FTP_ENABLE -eq 1 ] && ftp_backup
                [ $SFTP_ENABLE -eq 1 ] && sftp_backup
                [ $S3_ENABLE -eq 1 ] && s3_backup
        done
        [ $VERBOSE -eq 1 ] && echo "*** Backup completed ***"
        [ $VERBOSE -eq 1 ] && echo "*** Check backup files in ${dirDaily} ***"
}


pgdb_backup(){

	### Start database backups
 	DATABASES=$DB_NAMES
 
        db=""
        for db in $DATABASES
        do
                errorDuringBackup=""
                FILE_NAME="${db}_${filenameDaily}"
                FILENAMEPATH="${dirDaily}/$FILE_NAME"
                [ $VERBOSE -eq 1 ] && echo -en "Database> $db... \n"

 #               ${PGDUMP} --host ${PG_HOST} --username $user --format=custom --file ${FILENAMEPATH} --dbname={db}
touch ${FILENAMEPATH}
                if [ $? == 0 ]; then
                        # Update monthly/yearly backups
                        cp $FILENAMEPATH $dirMonthly/${db}_$filenameMonthly.dmp
                        cp $FILENAMEPATH $dirYearly/${db}_$filenameYearly.dmp
                        finalOutput="backup success"
                        [ $FTP_ENABLE -eq 1 ] && ftp_backup
                        [ $SFTP_ENABLE -eq 1 ] && sftp_backup
                        [ $S3_ENABLE -eq 1 ] && s3_backup
                else
                        finalOutput='backup error : pg_dump returned non-zero code'
                fi
                echo "$db   :: `du -sh ${FILENAMEPATH}`"  >> ${logfile}
                echo "$(date +%Y-%m-%d_%H:%M:%S) - $finalOutput" >> $logfile
        done
        [ $VERBOSE -eq 1 ] && echo "*** Backup completed ***"
        [ $VERBOSE -eq 1 ] && echo "*** Check backup files in ${dirDaily} ***"
}

### UTILITY FUNCTIONS  ###

### Check Configuratione file exists ###
check_config(){
	### Check if configuration file exists.
        [ ! -f $CONFIGFILE ] && close_on_error "Config file not found, make sure config file is correct"
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
	if [ $DB_TYPE == "MYSQL" ]; then
        [ ! -x $MYSQL ] && close_on_error "FILENAME $MYSQL does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $MYSQLDUMP ] && close_on_error "FILENAME $MYSQLDUMP does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $MYSQLCHECK ] && close_on_error "FILENAME $MYSQLCHECK does not exists. Make sure correct path is set in $CONFIGFILE."
	fi
	if [ $DB_TYPE == "PGSQL" ]; then
        [ ! -x $PSQL ] && close_on_error "FILENAME $PSQL does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $PGDUMP ] && close_on_error "FILENAME $PGDUMP does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $PGCHECK ] && close_on_error "FILENAME $PGCHECK does not exists. Make sure correct path is set in $CONFIGFILE."
	fi

}

### Check if database connectin is working...
check_mysql_connection(){
        ${MYSQLCHECK} ${MYSQLCREDENTIAL} -h ${MYSQL_HOST} -P ${MYSQL_PORT} ping | ${GREP} 'alive'>/dev/null
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
        # keep 1 backup per day, for the last 30 days
        find $dirDaily -type f -name "*\.zip" -mtime +30 -delete

        # keep 1 backup per month, for the last 12 months (360 = 30 x 12)
        find $dirMonthly -type f -name "*\.zip" -mtime +360 -delete

        # keep 1 backup per year, for the last 10 years (3600 = 30 x 12 x 10)
        find $dirYearly -type f -name "*\.zip" -mtime +3600 -delete

}

### Send report email
send_report(){
	if [ $SENDEMAIL -eq 1 ]
	then
			cat ${logfile} | mail -vs "Database dump report for `date +%D`" ${EMAILTO}
	fi
}



### main ####
check_config
check_cmds
if [ $DB_TYPE == "MYSQL" ]; then
        #check_mysql_connection
        #mysqldb_backup
fi
if [ $DB_TYPE == "PGSQL" ]; then
        #check_pgsql_connection
        pgdb_backup
fi
#clean_old_backups
send_report
