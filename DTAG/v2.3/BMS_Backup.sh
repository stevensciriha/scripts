#!/bin/ksh

# v1.9 ssciriha Jan 17th 2012
# BMS Backup Script
# Performs the following backups:

. /etc/BWC/config.sh
. $BWC_HOME/util/environment.sh



#Update the following variable with the latest postgres user password
export PGPASSWORD="postgres"
# The age variable represent the retention period
age="1"

#set backup directory
BACKUP_DIR="/doxstore2/backup"

#set temp directory under /backup
TEMP_DIR="$BACKUP_DIR/temp"

#set default file list location 
# it is hidden to ensure no changes are made to it
DEFAULT_FILE_LIST="/opt/Amdocs/backup_scripts/system_backup_filelist.conf"

#this is the text file the tar command will run on
FILE_LIST="/var/tmp/filelist.txt"

#set user-configurable file list location
USER_FILE_LIST="/opt/Amdocs/backup_scripts/user_backup_filelist.conf"

#set location for backup log
LOG=$BACKUP_DIR/backup.log

#RMA rules engine root credentials
XPC_USERNAME="root"
XPC_PASSWORD="root"

# The age variable represent the retention period
age="1"

# initialize ERROR and WARNING counters
error=0
warn=0


#########################
# create_backup_file
#########################

create_backup_file(){

# make sure directory exists
  if [ ! -d $BACKUP_DIR ]
  then
    mkdir -p $BACKUP_DIR
    if [ $? != 0 ]
    then
    	echo "ERROR: Could not create backup directory. Exiting..." >> $LOG
        ((error++))     
	return 4
    fi   
    chmod 755 $BACKUP_DIR
  fi

# clear log
  echo "" > $LOG
  echo "Export starting at `date`..." >> $LOG

 # generate backup file name
  BACKUP_FILE="$BACKUP_DIR/BACKUP_`hostname`_`date '+PCRF.%d.%m.%y'`.tar"

# Check if temp directory has been created if yes delete it and recreate it, if not create it
if [ -d $TEMP_DIR ]
  then
    echo "WARNING: Temp directory already exists!! Recreating..." >> $LOG
    ((warn++))
    rm -rf $TEMP_DIR
    mkdir $TEMP_DIR
    chmod 777 $TEMP_DIR
    if [ $? != 0 ]
       then
          return 4
    fi
 else
    mkdir $TEMP_DIR
    chmod 777 $TEMP_DIR
    if [ $? != 0 ]
       then
          return 4
    fi
fi

# Copy contents of default system filelist.txt file to working file
if [ -f $DEFAULT_FILE_LIST ] 
   then
     if [ -f $FILE_LIST ]
     	then
             rm $FILE_LIST
     fi
     cp -p $DEFAULT_FILE_LIST $FILE_LIST
     if [  $? != 0 ]
       then
          return 4
     fi
   else
    echo "ERROR: $DEFAULT_FILE_LIST does not exist or has been deleted, please create and restart. Exiting..." >> $LOG
    ((error++))
    exit_subroutine  
fi     

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
      if [ -f $FILE_LIST ]
      then
        echo $1 >> $FILE_LIST
        return $?
      else
        echo "ERROR: $FILE_LIST does not exist! Exiting..." >> $LOG
        ((error++))
        exit_subroutine
      fi
    else
        echo "WARNING: $1 does not exist or has been corrupted..." >> $LOG
        ((warn++))
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
    CONFIG_EXPORT_NAME="$TEMP_DIR/$arg.config.tar"
    tar -chf $CONFIG_EXPORT_NAME $INSTANCE_CURRENT/config --exclude \*.jar --exclude \*.exe --exclude \*.jsp >>/dev/null 
    add_to_tar $CONFIG_EXPORT_NAME
    if [ $? != 0 ]
    then
      return 4
    fi
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
 if [ -d $BACKUP_DIR ]
 then
 echo "performing backup file cleanup, deleting files older then $age days..." >> $LOG
 find $BACKUP_DIR -name "*BACKUP*" -mtime +$age -exec rm {} \; >> /dev/null
 else
         echo "ERROR: Backup Directory $BACKUP_DIR does not exist" >> $LOG
         ((error++))
 fi

}

get_package_versions() {


echo "Exporting system and application package versions..." >> $LOG
PackageVersions="$TEMP_DIR/PackageVersions.`date '+%d%m%y'`.txt"
rpm -qa > $PackageVersions
add_to_tar $PackageVersions
if [ $? != 0 ]
          then
          #  rm $PackageVersions
            return 3
          fi
        #  rm $PackageVersions

}
#
# Perform cleanup of all backup tarfiles older then $age
#
backup_cleanup() {

 #look for all files with an modified time greater then $age
 if [ -d $BACKUP_DIR ]
 then
 echo "performing backup file cleanup, deleting files older then $age days..." >> $LOG
 find $BACKUP_DIR -name "*BACKUP*" -mtime +$age -exec rm {} \; >> /dev/null
 else
         echo "ERROR: Backup Directory $BACKUP_DIR does not exist" >> $LOG
         ((error++))
 fi

}

get_package_versions() {


echo "Exporting system and application package versions..." >> $LOG
PackageVersions="$TEMP_DIR/PackageVersions.`date '+%d%m%y'`.txt"
rpm -qa > $PackageVersions
add_to_tar $PackageVersions
if [ $? != 0 ]
          then
          #  rm $PackageVersions
            return 3
          fi
        #  rm $PackageVersions

}


compress_tarfile() {

if [ ! -f $BACKUP_FILE.gz ]
then
gzip $BACKUP_FILE >> /dev/null
if (($? != 0))
then
  echo "WARNING: Failed to compress tarfile..." >> $LOG
  ((warn++))
fi
else
echo "WARNING: Could not compress...$BACKUP_FILE.gz already exists!" >> $LOG
((warn++))
return 4
fi
}

perform_tar_operation() {

# This tar command will read the list of files and directories of $FILE_LIST and archive, if they exist
echo "Performing tar archive operation..." >> $LOG
tar -chf $BACKUP_FILE --ignore-failed-read --files-from=$FILE_LIST --wildcards >> /dev/null
if (($? != 0))
then
    return 4
fi

# Delete temp directory
if [ -d $TEMP_DIR ]
	then
            rm -rf $TEMP_DIR
        else 
            echo "ERROR: Could not delete temporary directory..." >> $LOG
            ((error++))
fi

# Delete temp filelist
if [ -f $FILE_LIST ]
        then
            rm -rf $FILE_LIST
        else
            echo "ERROR: Could not delete temporary file list..." >> $LOG
            ((error++))
fi
}

restore_original_filelist() {
# restore original $FILE_LIST to undo changes made by script

if [ -f /var/tmp/.filelist.txt.bak ]
	then
		cp -p /var/tmp/.filelist.txt.bak $FILE_LIST
		if (($? != 0))
			then
    				return 5
		fi
fi

}

append_network_scripts() {

# This function is required to backup the network scripts because the tar command doesnt take wildcards when using a list of files
# Add the wildcard entries you want to have backed up to the following array

set -A Configs_List "*ifcfg*" "route*"
   for config in ${Configs_List[*]}
        do
		find /etc/sysconfig/network-scripts -name $config >> $FILE_LIST
		if (($? != 0))
			then
   				echo "WARNING: Could not find network scripts. Skipping..." 
                                ((warn++))
		fi
        done 

}

backup_user_configs() {

if [ -f $USER_FILE_LIST ]
	then
            echo "User-Configurable file list detected. Script will attempt to backup all specified files..." >> $LOG
            cat $USER_FILE_LIST >> $FILE_LIST
	    if [ $? != 0 ]
           	then
            		return 3
            fi
	
	else
            echo "WARNING: No User-Configurable file list detected. Skipping..." >> $LOG
            ((warn++))
            return 0
fi
}
backup_snmp_config() {
  #Backup snmp config directory
    if [ -d "/WideSpan/snmp/config" ]
  then
    echo "exporting snmp configuration directory /WideSpan/snmp/config..." >> $LOG
    SNMP_EXPORT_NAME="$TEMP_DIR/snmp.config.tar"
    tar -chf $SNMP_EXPORT_NAME /WideSpan/snmp/config --exclude \*.jar --exclude \*.exe --exclude \*.jsp >>/dev/null
    if [ $? != 0 ]
        then 
            return 4
    fi
    add_to_tar $SNMP_EXPORT_NAME
    if [ $? != 0 ]
    then
#      rm $SNMP_EXPORT_NAME
      return 4
    fi
#    rm $SNMP_EXPORT_NAME
  else
    echo "WARNING: There is no snmp config directory to export." >> $LOG
    ((warn++))
  fi
}

validate_tar_filelist() {

 if [ -f $FILE_LIST ]
	then
             while read config
		do
                	if [ -f $config ]
  		 	then	
                        	echo "Backing up the following file: $config..." >> $LOG
		        elif [ -d $config ] 
			then
   				echo "Backing up the following directory: $config..." >> $LOG           
			else
                                echo "WARNING: $config does not exist. Skipping..." >> $LOG
                                ((warn++))
		 	fi	
		done <"$FILE_LIST"
 fi          
}

exit_subroutine() {
  
 if [ $error -gt 0 ]
        then
            echo "!!Backup Complete with ERRORS!! Check logs above for further information..." >> $LOG
            echo "If created...the archive can be found at ${BACKUP_FILE}.gz" >> $LOG
            exit
        else
            echo "Backup Complete with $warn warnings..." >> $LOG
            echo "The archive can be found at ${BACKUP_FILE}.gz" >> $LOG
            exit
 fi
}

get_params_config() {

        #Backup params directory
    if [ -d "/WideSpan/stage/params" ]
  then
    echo "exporting params directory /WideSpan/stage/params..." >> $LOG
    PARAMS_EXPORT_NAME="$TEMP_DIR/params.config.tar"
    tar -chf $PARAMS_EXPORT_NAME /WideSpan/stage/params --exclude \*.jar --exclude \*.exe --exclude \*.jsp >>/dev/null
    add_to_tar $PARAMS_EXPORT_NAME
    if [ $? != 0 ]
    then
      return 4
    fi
  else
    echo "WARNING: There is no params directory to export." >> $LOG
    ((warn++))
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

#perform_postgres_backup
#if (($? != 0))
#then
#  echo "Failed to perform postgres backup" >> $LOG
#fi

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

get_params_config
if (($? != 0))
then
  echo "Failed to export params configs" >> $LOG
fi

compress_tarfile
if (($? != 0))
then
  echo "Failed to compress logfile" >> $LOG
fi

echo "Complete. The archive can be found at ${BACKUP_FILE}.tar.gz" >> $LOG

