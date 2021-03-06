#!/bin/ksh

# v1.2 ssciriha Jan 17th 2012 
# DRA/SLF Backup Script
# Performs the following backups:

. /etc/BWS/BPC/config.sh
. $BPC_HOME/util/environment.sh

LOG=${BPC_HOME}/backup/backup.log

# Because script is to be run in crontab credentials need to be hardcoded 
XPC_USERNAME="root"
XPC_PASSWORD="root"

# The age variable represent the retention period
age="1"

###################################################################
#Create the backup directory the tarfile directory and the tarfile
###################################################################
create_backup_file(){
  # make sure directory exists
  BACKUP_DIR=${BPC_HOME}/backup

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
  fi
 # generate backup file name
  BACKUP_FILE="$TARFILE_DIR/BACKUP_`hostname`_`date '+DRA.%d.%m.%y'`"
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
      # The rgmgr utility lives under the SLF instance directory so we need th SLF instance name

      if [[ $arg != "DRASLF" && $arg != "SNMP" && $arg != "TimesTen" ]]
         then
         SLF_INSTANCE_NAME=$arg
      fi
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

get_configs(){
   # Create an array with all the configs that require backing up 
   set -A Configs_List "$BPC_HOME/slf-config.xml" "/etc/corosync/corosync.conf" "/opt/bpc/is/DRASLF/config/dra-slf-config.xml"
   
   #Because of permission issues the files will be cat'ed instead of cp'ed 
   #check if each config exists and if it does do cludge that strips filename from config and backup file 
   for config in ${Configs_List[*]}
	do 
            if [ -r $config ];then
            echo "Exporting $config" >> $LOG
            set -A Filename_Array `echo $config | sed -e 's/\// /g'` 
            MAX_ARRAY_NUM=${#Filename_Array[*]}     
            Filename=`echo ${Filename_Array[$MAX_ARRAY_NUM-1]}` 
            Absolute_Filename="$TARFILE_DIR/$Filename"
            cat $config > $Absolute_Filename

            if [ -f $Absolute_Filename ]
                then
            add_to_tar $Absolute_Filename
                if [ $? != 0 ]
                     then
                     rm  $Absolute_Filename
                     return 3
                fi
                rm $Absolute_Filename
             fi
 
   else
            echo "$config does not exist or is not accessible" >> $LOG
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
        TAR_OPTIONS="-cf"
      else
        TAR_OPTIONS="-rf"
      fi

      tar $TAR_OPTIONS ${BACKUP_FILE}.tar $1 >> /dev/null
      return $?
    fi
  fi
}

###########################################################
# Perform the CRM configuraton export using the crm utility 
###########################################################
perform_CRM_config_export() {
echo "Exporting CRM configuration..." >> $LOG

# use crm tool to save DRA configuration to a textfile
CRM_OUTPUT=`crm configure save $TARFILE_DIR/CRM_config.txt`
if [ "x$CRM_OUTPUT" = "x" ]
then
echo "Error: Could not backup crm configuration" >> $LOG
return 5
fi 
# isnertw effor checking
CRM_FILENAME="$TARFILE_DIR/CRM_config.txt"
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
ACTIVE_PARTITION=`/opt/bpc/is/$SLF_INSTANCE_NAME/bin/rgmgr list|grep " ACTIVE " |sed 's/  */ /'g |cut -d' ' -f2 |tail -1`
/opt/bpc/is/$SLF_INSTANCE_NAME/bin/rgmgr show $ACTIVE_PARTITION > $ACTIVE_PARTITION_OUTPUT

add_to_tar $ACTIVE_PARTITION_OUTPUT
if [ $? != 0 ]
    then
      rm $ACTIVE_PARTITION_OUTPUT
      return 4
fi
    rm $ACTIVE_PARTITION_OUTPUT
}

perform_SDC_config_export() {
  echo "Exporting DRA configuration directory /opt/traffix/sdc/config..." >> $LOG
  if [ -d /opt/traffix/sdc/config ]
  then
    CONFIG_EXPORT_NAME="$TARFILE_DIR/DRA_SDC.config.zip"
#    echo "DEBUG:CONFIG_EXPORT_NAME:$CONFIG_EXPORT_NAME" >> $LOG
    zip -r $CONFIG_EXPORT_NAME /opt/traffix/sdc/config -x \*.jar \*.exe \*.jsp >> /dev/null
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

backup_cleanup() {

echo "performing backup file cleanup, deleting files older then $age days..." >> $LOG
 find $TARFILE_DIR -name "*BACKUP*" -mtime +$age -exec rm {} \;

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
set -A Configs_List "/etc/sysconfig/network-scripts/*if*" "/etc/sysconfig/network" "/etc/modprobe.conf" "/etc/hosts" "/etc/syslog.conf" "/etc/passwd" "/etc/group" "/etc/shadow" "/etc/sysconfig/network-scripts/route-*" "/etc/sysctl.conf" "/etc/sysconfig/syslog" "/etc/ntp.conf" "/etc/sysconfig/selinux" "/etc/yum.repos.d/rhel-dvd-repo"    

   #Because of permission issues the files will be cat'ed instead of cp'ed 
   #check if each config exists and if it does do cludge that strips filename from config and backup file 
   for config in ${Configs_List[*]}
	do 
            if [ -r $config ];then
            echo "Exporting $config" >> $LOG
            set -A Filename_Array `echo $config | sed -e 's/\// /g'` 
            MAX_ARRAY_NUM=${#Filename_Array[*]}     
            Filename=`echo ${Filename_Array[$MAX_ARRAY_NUM-1]}` 
            Absolute_Filename="$TARFILE_DIR/$Filename"
            cat $config > $Absolute_Filename

            if [ -f $Absolute_Filename ]
                then
            add_to_tar $Absolute_Filename
                if [ $? != 0 ]
                     then
                     rm  $Absolute_Filename
                     return 3
                fi
                rm $Absolute_Filename
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

gzip $BACKUP_FILE.tar >> /dev/null
if (($? != 0))
then
  echo "Failed to compress tarfile..." >> $LOG
fi
}

################
#MAIN
################

create_backup_file

echo "" > $LOG
echo "Export starting at `date`..." >> $LOG

INSTANCE_HOME="$BPC_HOME/is"
export INSTANCE_HOME

get_parmdbs
if (($? != 0))
then
  echo "Failed to export parmdb files" >> $LOG
fi


perform_active_partition_export
if (($? != 0))
then
  echo "Failed to export active partition" >> $LOG
fi

get_configs
if (($? != 0))
then
  echo "Failed to export one or more of the individual configs" >> $LOG
fi
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
  echo "Failed to export package version" >> $LOG
fi

get_system_configs
if (($? != 0))
then
  echo "Failed to export system configs" >> $LOG
fi

backup_cleanup
if (($? != 0))
then
  echo "Failed to perform backup cleanup" >> $LOG
fi

compress_tarfile
if (($? != 0))
then
  echo "Failed to compress logfile" >> $LOG
fi
echo "Complete. The archive can be found at ${BACKUP_FILE}.tar" >> $LOG
