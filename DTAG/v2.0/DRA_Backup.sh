#!/bin/ksh

# v1.9 ssciriha Jan 17th 2012
# **DRA Backup Script for NON-SLFDRA node**
# Performs the following backups:

. /etc/BWS/BPC/config.sh
#. $BPC_HOME/util/environment.sh

TRAFFIX_HOME=/opt
LOG=$TRAFFIX_HOME/backup/backup.log

INSTANCE_HOME="$BPC_HOME/is"

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

# Because script is to be run in crontab credentials need to be hardcoded
XPC_USERNAME="root"
XPC_PASSWORD="root"

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

#########################
# get_parmdbs
#########################

get_parmdbs(){
  echo "Exporting instance configurations..." >> $LOG
  for arg in $(ls $INSTANCE_HOME)
  do
    if [ -d $INSTANCE_HOME/$arg ]
    then
      INSTANCE_CURRENT=${INSTANCE_HOME}/$arg
      # we only want actual instance directories
      if [ -f ${INSTANCE_CURRENT}/parmdb -a -f ${INSTANCE_CURRENT}/version ]
      then
        # we want to ignore the special *_dfn instances
        if [[ ${arg##${arg%%_dfn}} = "_dfn" ]]
        then
          continue
        fi

        echo "Exporting instance ${arg}..." >> $LOG
        # create a temp copy of the parmdb with a traceable name
        PARMDB_NAME=${TEMP_DIR}/`cat ${INSTANCE_CURRENT}/version`.${arg}.parmdb
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
    fi
  done
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

if [ -f $USER_FILE_LIST ]
	then
            echo "User-Configurable file list detected. Script will attempt to backup all specified files..." >> $LOG
            cat $USER_FILE_LIST >> $FILE_LIST
	    if [ $? != 0 ]
           	then
            		return 3
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

###########################################################
# Perform the CRM configuraton export using the crm utility
###########################################################
perform_CRM_config_export() {
echo "Exporting CRM configuration..." >> $LOG

CRM_FILENAME="/tmp/CRM_config.txt"
PATH=$PATH:/usr/sbin
export PATH
# use crm tool to save DRA configuration to a textfile
crm configure save $CRM_FILENAME
if [ $? != 0 ]
   then
   echo "Problem exporting CRM configuration..." >> $LOG
   rm $CRM_FILENAME
   return 5
fi

# isnertw effor checking
add_to_tar $CRM_FILENAME
if [ $? != 0 ]
    then
      rm $CRM_FILENAME
      return 4
fi
    rm $CRM_FILENAME
}

perform_active_partition_export(){
echo "Exporting Active Subscriber Partition..." >> $LOG

export XPC_USERNAME
export XPC_PASSWORD
ACTIVE_PARTITION_OUTPUT=$TARFILE_DIR/Active_Partition_Config.txt
cp /opt/bpc/is/$SLF_INSTANCE_NAME/bin/rgmgr /tmp/rgmgr
perl -i -pe 's/\. \$BPC_HOME\/util\/environment\.sh/#\. \$BPC_HOME\/util\/environment\.sh/g' /tmp/rgmgr
ACTIVE_PARTITION=`/tmp/rgmgr list|grep " ACTIVE " |awk '{sub(/^/, " ")};1' | sed 's/  */ /'g |cut -d' ' -f2 |tail -1`
/tmp/rgmgr show $ACTIVE_PARTITION > $ACTIVE_PARTITION_OUTPUT
rm /tmp/rgmgr

add_to_tar $ACTIVE_PARTITION_OUTPUT
if [ $? != 0 ]
    then
      rm $ACTIVE_PARTITION_OUTPUT
      return 4
fi
    rm $ACTIVE_PARTITION_OUTPUT
}


perform_SDC_config_export() {
  echo "Exporting DRA configuration directories /opt/traffix/sdc/config, /opt/traffix/sdc/data/backup and /etc/corosync..." >> $LOG
  if [[ -d /opt/traffix/sdc/config && -d /opt/traffix/sdc/data/backup ]]
  then
    CONFIG_EXPORT_NAME="$TARFILE_DIR/DRA_SDC.config.zip"
#    echo "DEBUG:CONFIG_EXPORT_NAME:$CONFIG_EXPORT_NAME" >> $LOG
    zip -r $CONFIG_EXPORT_NAME /opt/traffix/sdc/config /opt/traffix/sdc/data/backup /etc/corosync -x \*.jar \*.exe \*.jsp >> /dev/null
    add_to_tar $CONFIG_EXPORT_NAME
    if [ $? != 0 ]
    then
      rm $CONFIG_EXPORT_NAME
      return 4
    fi
    rm $CONFIG_EXPORT_NAME
  else
    echo "There is no DRA config directory to export." >> $LOG
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

case $SLF_NODE in  
		  "1")
		  get_parmdbs
		  perform_active_partition_export
		  ;;
	  	  "*")
	 	  echo "DRA Node is non-SLF. Skipping SLF backup section..." >> $LOG
		  ;;
esac

perform_CRM_config_export
if (($? != 0))
then
  echo "Failed to export CRM config" >> $LOG
fi

perform_SDC_config_export
if (($? != 0))
then
  echo "Failed to export SDC config" >> $LOG
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

