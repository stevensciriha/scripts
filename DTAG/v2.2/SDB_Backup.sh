#!/bin/ksh

# v2.0 ssciriha Mar 15th 2012
# v2.3 ssciriha May 7th 2012
# changed mtime option from +1 to -1 for db backup listing
# SDB Backup Script

# This new version supersedes all the previous v1.x scripts 

. /u01/app/oracle/widespan/scripts/env_server.sh
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

# The age variable represent the retention period
age="1"

# initialize ERROR and WARNING counters
error=0
warn=0

#set Oracle_Base directory
ORACLE_BASE=/u01/app/oracle

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
    fi   
    chmod 755 $BACKUP_DIR
  fi

# clear log
  echo "" > $LOG
  echo "Export starting at `date`..." >> $LOG

 # generate backup file name
  BACKUP_FILE="$BACKUP_DIR/BACKUP_`hostname`_`date '+SDB.%d.%m.%y'`.tar"

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

perform_SDB_config_export() {
  echo "Exporting ORACLE configuration directory $ORACLE_HOME/network/admin..." >> $LOG
  if [ -d $ORACLE_HOME/network/admin ]
  then
    CONFIG_EXPORT_NAME="$TEMP_DIR/SDB.config.tar"
    tar -chf $CONFIG_EXPORT_NAME $ORACLE_HOME/network/admin --exclude \*.jar --exclude \*.exe --exclude \*.jsp >>/dev/null
    add_to_tar $CONFIG_EXPORT_NAME
    if [ $? != 0 ]
    then
      return 4
    fi
  else
    echo "There is no SDB config directory to export." >> $LOG
  fi
}

get_db_backup() {

for arg in $(find $DB_BACKUP_DIR -mtime -1) 
	do
		echo "Adding database backup files to tarfile..." >> $LOG
		if [ -f $arg ]
			then
				add_to_tar $arg
		fi
	done
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
         echo "Backup Directory $BACKUP_DIR does not exist" >> $LOG
 fi

}

get_package_versions() {

echo "Exporting system and application package versions..." >> $LOG
PackageVersions="$TEMP_DIR/PackageVersions.`date '+%d%m%y'`.txt"
rpm -qa > $PackageVersions
add_to_tar $PackageVersions
if [ $? != 0 ]
          then
            return 3
          fi

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


get_provs_config() {

        #Backup Provserver config directory
    if [ -d "/WideSpan/config/provserver" ]
  then
    echo "exporting Provserver configuration directory /WideSpan/config/provserver..." >> $LOG
    PROV_EXPORT_NAME="$TEMP_DIR/provserver.config.tar"
    tar -chf $PROV_EXPORT_NAME /WideSpan/config/provserver --exclude \*.jar --exclude \*.exe --exclude \*.jsp >>/dev/null
    add_to_tar $PROV_EXPORT_NAME
    if [ $? != 0 ]
    then
      return 4
    fi
  else
    echo "There is no provserver config directory to export." >> $LOG
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
 
get_database_backup_dir() {
        
        . /u01/app/oracle/widespan/scripts/env_server.sh
	if [ -f $ORACLE_BASE/widespan/backups/database_backup.cf ]
		then
                      DB_BACKUP_DIR="`cat $ORACLE_BASE/widespan/backups/database_backup.cf | grep directory | cut -d= -f2`"
                  #    echo $DB_BACKUP_DIR | egrep -q '\/$'
                  #    if (($? = 0))
	          #			then
                  #                  DB_BACKUP_DIR=$DB_BACKUP_DIR
		      
                else
                      echo "Database configuration file $ORACLE_BASE/widespan/backups/database_backup.cf does not exist..." >> $LOG
                      return 4
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

export_CTA_parmdb() {

if [ -f /etc/BWC/config.sh ]
	then 
            . /etc/BWC/config.sh
            INSTANCE_HOME="$BWC_HOME/is" 
        else
            echo "WARNING: CTA agent not detected...Could not backup!" >> $LOG
            ((warn++))
            return 4
fi


 echo "Exporting instance configurations..." >> $LOG
  for arg in $(ls $INSTANCE_HOME)
  do
    if [ -d $INSTANCE_HOME/$arg ]
    then
      INSTANCE_CURRENT=${INSTANCE_HOME}/$arg
      # we only want actual instance directories
        echo "Exporting instance ${arg}..." >> $LOG
        # create a temp copy of the parmdb with a traceable name
       PARMDB_NAME=$TEMP_DIR/`cat ${INSTANCE_CURRENT}/version`.${arg}.parmdb

       cp -fp ${INSTANCE_CURRENT}/parmdb $PARMDB_NAME

        if [ -f $PARMDB_NAME ]
        then
          add_to_tar $PARMDB_NAME
          if [ $? != 0 ]
          then
            return 3
          fi
        fi

    fi
   done

if [ -f /etc/BWS/BPC/config.sh ]
        then
        # Reset INSTANCE_HOME variable to BPC_HOME
        INSTANCE_HOME="$BPC_HOME/is"
fi
}

backup_user_configs() {
if (($? != 0))
then
  echo "WARNING: Failed to backup provisioning directory" >> $LOG
  ((warn++))
fi

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

################
#MAIN
################

create_backup_file
if (($? != 0))
then
  echo "ERROR: Failed to create Backup Directory $BACKUP_DIR..." >> $LOG
  ((error++))
  exit_subroutine
fi

backup_cleanup
if (($? != 0))
then
        echo "ERROR: Failed to perform backup cleanup..." >> $LOG
        ((error++))
fi

append_network_scripts
if (($? != 0))
then
  echo "WARNING: Failed to export network scripts" >> $LOG
  ((warn++))
fi

backup_user_configs
if (($? != 0))
then
  echo "WARNING: Failed to backup user-configurable configuration files" >> $LOG
  ((warn++))
fi
 

validate_tar_filelist
if (($? != 0))
then
  echo "WARNING: Failed to validate tar filelist" >> $LOG
  ((warn++))
fi

export_CTA_parmdb
if (($? != 0))
then
  echo "WARNING: Failed to export CTA parmdb files" >> $LOG
  ((warn++))
fi

get_package_versions
if (($? != 0))
then
  echo "WARNING: Failed to export package version" >> $LOG
  ((warn++))
fi

backup_snmp_config
if (($? != 0))
then
  echo "WARNING: Failed to backup snmp configuration" >> $LOG
  ((warn++))
fi

get_params_config
if (($? != 0))
then
  echo "WARNING: Failed to backup params files" >> $LOG
  ((warn++))
fi

get_provs_config
if (($? != 0))
then
  echo "WARNING: Failed to backup provisioning directory" >> $LOG
  ((warn++))
fi

get_database_backup_dir
if (($? != 0))
then
  echo "ERROR: Failed to retreive database backup directory" >> $LOG
  ((error++))
fi


get_db_backup
if (($? != 0))
then
  echo "WARNING: Failed to backup database" >> $LOG
  ((warn++))
fi

perform_SDB_config_export
if (($? != 0))
then
  echo "WARNING: Failed to backup SDB network directory" >> $LOG
  ((warn++))
fi

perform_tar_operation
if (($? != 0))
then
       echo "ERROR: Failed to create archive. Exiting..." >> $LOG
       ((error++))
       exit_subroutine
fi

compress_tarfile
if (($? != 0))
then
  	echo "WARNING: Failed to compress logfile" >> $LOG
  	((warn++))
  	exit_subroutine
fi

exit_subroutine

