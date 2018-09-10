#!/bin/ksh

# v1.8 ssciriha Jan 17th 2012
# DRA/SLF Backup Script
# Performs the following backups:

. /etc/BWS/BPC/config.sh
#. $BPC_HOME/util/environment.sh

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
   set -A Configs_List "$BPC_HOME/slf-config.xml" "/etc/corosync/corosync.conf" "/opt/bpc/is/DRASLF/config/dra-slf-config.xml" "/etc/logrotate-traffix.conf" "/etc/rsyslog.conf" "/etc/snmp/snmpd.conf" "/etc/ssh/sshd_config" "/etc/sysconfig/ip6tables" "/etc/sysconfig/iptables" "/opt/traffix/config/fep*.xml" "/opt/traffix/config/defaultLBConfiguration.xml" "/opt/traffix/config/*" "/etc/keepalived/keepalived.conf" "/etc/ipsec*"

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

compress_tarfile
if (($? != 0))
then
  echo "Failed to compress logfile" >> $LOG
fi
echo "Complete. The archive can be found at ${BACKUP_FILE}.tar.gz" >> $LOG


