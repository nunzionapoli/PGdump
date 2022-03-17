#!/usr/bin/env bash

# 30 2 * * * bash /path/to/script/backup-database.bash
# This will run the script once every day at 2:30 AM. 

# da https://wimantis.ninja/bash-script-to-create-daily-monthly-and-yearly-mysql-database-backups/

# This script creates daily + monthly + yearly mysql database backups locally (on the same server)
# It DOESN'T notify you by email if an error happens, and DOESN'T store backups on a cloud service !
# It DOES save a log file with the history of errors/success tho :)

# --- Edit those settings !
mysqlDbUser='root'
mysqlDbName='database_name_here'
backupDirectory='/path/to/backups/directory'
# ---

dirDaily=$backupDirectory/daily
dirMonthly=$backupDirectory/monthly
dirYearly=$backupDirectory/yearly
filenameDaily=backup-$(date +%Y-%m-%d)
filenameMonthly=backup-$(date +%Y-%m)
filenameYearly=backup-$(date +%Y)
sqlfile=$dirDaily/$filenameDaily.sql
zipfile=$dirDaily/$filenameDaily.zip
logfile=$backupDirectory/history.log

# Make sure directories exists
mkdir -p $dirDaily
mkdir -p $dirMonthly
mkdir -p $dirYearly

# Create daily backup
mysqldump -u $mysqlDbUser $mysqlDbName > $sqlfile

errorDuringBackup=""
if [ $? == 0 ]; then
  # Compress daily backup
  zip -q -j $zipfile $sqlfile

  if [ $? == 0 ]; then
    # Update monthly/yearly backups
    cp $zipfile $dirMonthly/$filenameMonthly.zip
    cp $zipfile $dirYearly/$filenameYearly.zip
  else
    errorDuringBackup='failed to compress backup'
  fi

  # Remove non-compresed file
  rm $sqlfile
else
  errorDuringBackup='mysqldump returned non-zero code'
fi

# keep 1 backup per day, for the last 30 days
find $dirDaily -type f -name "*\.zip" -mtime +30 -delete

# keep 1 backup per month, for the last 12 months (360 = 30 x 12)
find $dirMonthly -type f -name "*\.zip" -mtime +360 -delete

# keep 1 backup per year, for the last 10 years (3600 = 30 x 12 x 10)
find $dirYearly -type f -name "*\.zip" -mtime +3600 -delete

# Output result
finalOutput=''
if ! [ -z "$errorDuringBackup" ] ; then
  finalOutput="backup error : $errorDuringBackup"
else
  finalOutput="backup success"
fi

echo "$(date +%Y-%m-%d_%H:%M:%S) - $finalOutput" >> $logfile
echo $finalOutput