#!/bin/ksh

# v1.5 ssciriha Jan 17th 2012
# BMS Backup Script
# Performs the following backups:

. /etc/BWC/config.sh
. $BWC_HOME/util/environment.sh


LOG=${BWC_HOME}/backup/backup.log

# Because script is to be run in crontab credentials need to be hardcoded
XPC_USERNAME="root"
XPC_PASSWORD="root"

#Update the following variable with the latest postgres user password
export PGPASSWORD="postgres"
# The age variable represent the retention period
age="1"

###################################################################
#Create the backup directory the tarfile directory and the tarfile
###################################################################
create_backup_file(){
  # make sure directory exists
  BACKUP_DIR=${BWC_HOME}/backup

  export BACKUP_DIR
  if [ ! -d $BACKUP_DIR ]
  then
    mkdir $BACKUP_DIR
  fi

#make tar file directory
  TARFILE_DIR=$BACKUP_DIR/TARFILE
  export TARFILE_DIR
 if [ ! -d $TARFILE_DIR ]
  then
    mkdir $TARFILE_DIR
    chmod 777 $TARFILE_DIR
  fi
 # generate backup file name
  BACKUP_FILE="$TARFILE_DIR/BACKUP_`hostname`_`date '+BMS.%d.%m.%y'`"
  export BACKUP_FILE

}

get_parmdbs(){
  echo "Exporting instance configurations..." >> $LOG
  for arg in $(ls $INSTANCE_HOME)
  do
    if [ -d $INSTANCE_HOME/$arg ]
    then
      INSTANCE_CURRENT=${INSTANCE_HOME}/$arg
      # we only want actual instance directories
        echo "Exporting instance ${arg}..." >> $LOG
        # create a temp copy of the parmdb with a traceable name
       PARMDB_NAME=$TARFILE_DIR/`cat ${INSTANCE_CURRENT}/version`.${arg}.parmdb

       cp -f ${INSTANCE_CURRENT}/parmdb $PARMDB_NAME

        if [ -f $PARMDB_NAME ]
        then
          add_to_tar $PARMDB_NAME
          if [ $? != 0 ]
          then
            rm $PARMDB_NAME
            return 3
          fi
          rm $PARMDB_NAME
        fi

    fi
  done



}

#########################
# add_to_tar
# $1 file to add
#########################
add_to_tar(){
  if [ "x$1" != "x" ]
  then
    if [[ -f $1 ]]
    then
      if [ ! -f ${BACKUP_FILE}.tar ]
      then
        TAR_OPTIONS="-chf"
      else
        TAR_OPTIONS="-rhf"
      fi

      tar $TAR_OPTIONS ${BACKUP_FILE}.tar $1 >> /dev/null
      return $?
    fi
  fi
}


perform_BMS_config_export() {

  for arg in $(ls $INSTANCE_HOME)
  do
    if [ -d $INSTANCE_HOME/$arg ]
    then
      INSTANCE_CURRENT=${INSTANCE_HOME}/$arg
      # we only want actual instance directories
     fi
  echo "Exporting BMS configuration directory $INSTANCE_CURRENT/config..." >> $LOG
  if [ -d "$INSTANCE_CURRENT/config" ]
  then
    CONFIG_EXPORT_NAME="$TARFILE_DIR/$arg.config.zip"
    zip -r $CONFIG_EXPORT_NAME $INSTANCE_CURRENT/config -x \*.jar \*.exe \*.jsp >> /dev/null
    add_to_tar $CONFIG_EXPORT_NAME
    if [ $? != 0 ]
    then
      rm $CONFIG_EXPORT_NAME
      return 4
    fi
    rm $CONFIG_EXPORT_NAME
  else
    echo "There is no BMS config directory to export." >> $LOG
  fi
done
}

perform_postgres_backup() {

. /opt/postgres/9.1/pg91.env
DES_DATA_DIR=`cat ~postgres/scripts/pg_db.info | grep PGDATA | cut -d "=" -f 2`
DES_WAL_DEST=`cat ~postgres/scripts/pg_db.info | grep PGWALS | cut -d "=" -f 2`
DES_REPLICATION=`cat ~postgres/scripts/pg_db.info | grep PGREPLICATION | cut -d "=" -f 2`
PG_BACKUP="$TARFILE_DIR/pg_backup.tar"
# Set the marker for the beginning of the backup
echo "Starting postgres backup..." >> $LOG
echo "Setting the new backup marker." >> $LOG
if [ ! -f ${DES_WAL_DEST}/run_pg_backup.sh.marker ]; then
  touch ${DES_WAL_DEST}/run_pg_backup.sh.marker
else
  cat /dev/null > ${DES_WAL_DEST}/run_pg_backup.sh.marker
fi

echo "Removing old backup markers." >> $LOG
rm ${DES_WAL_DEST}/*.backup > /dev/null 2>&1

psql -c "SELECT pg_start_backup('Full_Backup', true)" >> /dev/null
if [ $? -gt 0 ]; then
  echo "There was an error putting the database into backup mode.  Exiting." >> $LOG
  exit 3
fi

tar -cvf $PG_BACKUP ${DES_DATA_DIR} >> /dev/null

if [ $? -gt 0 ]; then
  echo "There was an error creating the backup tarball.  Exiting." >> $LOG
  exit 5
fi
psql -c "SELECT pg_stop_backup()" >> /dev/null
if [ $? -gt 0 ]; then
  echo "There was an error putting the database into production mode.  Exiting." >> $LOG
  exit 3
fi

echo "Backing up WAL logs..." >> $LOG
find ${DES_WAL_DEST} -type f -newer ${DES_WAL_DEST}/run_pg_backup.sh.marker -exec tar -rPf $PG_BACKUP {} \;
if [ $? -gt 0 ]; then
echo "There was a problem adding WAL logs to the archive.  Exiting" >> $LOG
  exit 4
fi

add_to_tar $PG_BACKUP
 if [ $? != 0 ]
          then
            rm $PG_BACKUP
            return 3
          fi
          rm $PG_BACKUP

#
}

#
# Perform cleanup of all backup tarfiles older then $age
#
backup_cleanup() {

 #look for all files with an modified time greater then $age
 if [ -d $TARFILE_DIR ]
 then
 echo "performing backup file cleanup, deleting files older then $age days..." >> $LOG
 find $TARFILE_DIR -name "*BACKUP*" -mtime +$age -exec rm {} \; >> /dev/null
 else
         echo "Backup Directory $TARFILE_DIR does not exist" >> $LOG
 fi

}

get_package_versions() {

echo "Exporting system and application package versions..." >> $LOG
PackageVersions="$TARFILE_DIR/PackageVersions.`date '+%d%m%y'`.txt"
rpm -qa > $PackageVersions
add_to_tar $PackageVersions
if [ $? != 0 ]
          then
            rm $PackageVersions
            return 3
          fi
          rm $PackageVersions

}


get_system_configs() {

echo "Exporting system configuration files..." >> $LOG
 # Create an array with all the configs that require backing up
set -A Configs_List "/etc/sysconfig/network-scripts/*if*" "/etc/sysconfig/network" "/etc/modprobe.conf" "/etc/hosts" "/etc/syslog.conf" "/etc/passwd" "/etc/group" "/etc/shadow" "/etc/sysconfig/network-scripts/route-*" "/etc/sysctl.conf" "/etc/sysconfig/syslog" "/etc/ntp.conf" "/etc/sysconfig/selinux" "/etc/yum.repos.d/*"

   #check if each config exists and if it doesn't skip to the next config
   for config in ${Configs_List[*]}
        do
            if [ -r $config ];then
            echo "Exporting $config" >> $LOG

            add_to_tar $config
                if [ $? != 0 ]
                     then
                     echo "$config could not be added to backup file" >> $LOG
                     return 3
                fi

            else

            echo "$config does not exist or is not accessible" >> $LOG
            fi
        done


   #Backup snmp config directory
    if [ -d "/WideSpan/snmp/config" ]
  then
    echo "exporting snmp configuration directory /WideSpan/snmp/config..." >> $LOG
    SNMP_EXPORT_NAME="$TARFILE_DIR/snmp.config.zip"
    zip -r $SNMP_EXPORT_NAME /WideSpan/snmp/config -x \*.jar \*.exe \*.jsp >> /dev/null
    add_to_tar $SNMP_EXPORT_NAME
    if [ $? != 0 ]
    then
      rm $SNMP_EXPORT_NAME
      return 4
    fi
    rm $SNMP_EXPORT_NAME
  else
    echo "There is no snmp config directory to export." >> $LOG
  fi

}

compress_tarfile() {

if [ ! -f $BACKUP_FILE.tar.gz ]
then
gzip $BACKUP_FILE.tar >> /dev/null
if (($? != 0))
then
  echo "Failed to compress tarfile..." >> $LOG
fi
else
echo "ERROR: Could not compress...$BACKUP_FILE.tar.gz already exists!" >> $LOG
fi
}


################
#MAIN
################

create_backup_file
if (($? != 0))
then
  echo "Failed to create Backup Directory $TARFILE_DIR..." >> $LOG
  exit
fi

# clear log
echo "" > $LOG
echo "Export starting at `date`..." >> $LOG
backup_cleanup
if (($? != 0))
then
        echo "Failed to perform backup cleanup..." >> $LOG
fi


INSTANCE_HOME="$BWC_HOME/is"
export INSTANCE_HOME

get_parmdbs
if (($? != 0))
then
  echo "Failed to export parmdb files" >> $LOG
fi

perform_BMS_config_export
if (($? != 0))
then
  echo "Failed to export BMS configuration files" >> $LOG
fi

perform_postgres_backup
if (($? != 0))
then
  echo "Failed to perform postgres backup" >> $LOG
fi

get_package_versions
if (($? != 0))
then
  echo "Failed to export package version" >> $LOG
fi

get_system_configs
if (($? != 0))
then
  echo "Failed to export system configs" >> $LOG
fi

compress_tarfile
if (($? != 0))
then
  echo "Failed to compress logfile" >> $LOG
fi

echo "Complete. The archive can be found at ${BACKUP_FILE}.tar.gz" >> $LOG

