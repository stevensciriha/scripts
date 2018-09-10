#!/usr/bin/expect -f

# v1.1 ssciriha Jan 17th 2012 
# v1.2 ssciriha Feb 20th 2012 
# -added "set timeout -1" to fix timeout problem for longer scp operations
# This script uses scp and expect to retrieve the backup tarball from all the servers

set timeout -1
set pass "labbws"
set done 0
set local_backup_dir_BMS "/stage/BMS/"
set local_backup_dir_PCRF "/stage/PCRF/"
set local_backup_dir_DRA "/stage/DRA/"
set local_backup_dir_SDB "/stage/SDB/"
set local_backup_dir_SWITCH "/stage/SWITCH/"
set PCRF_PASS "labbws"
set PCRF_PATH "/opt/bpc/backup/TARFILE"
set PCRF_HOST "kll5029"
set DRA_PASS "labbws"
set DRA_PATH "/opt/bpc/backup/TARFILE"
set DRA_HOST "kll0057"
set BMS_PASS "labbws"
set BMS_PATH "/opt/bwc/backup/TARFILE"
set BMS_HOST "kll5033"
set SDB_PASS "labbws"
set SDB_PATH "/u01/app/oracle/widespan/backups/daily"
set SDB_HOST "kll5030"
set SWITCH_PASS "admin"
set SWITCH_HOST "192.168.155.48"
set current_date [exec date +%d.%m.%y]

# trick to pass in command-line args to spawn
#eval spawn scp $argv

#PCRF Section
spawn scp root@$PCRF_HOST:$PCRF_PATH/*$current_date* $local_backup_dir_PCRF
expect {
        "password:" {send "$PCRF_PASS\r"; exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$PCRF_PASS\r"; exp_continue}}
        eof 
}


#DRA Section
spawn scp root@$DRA_HOST:$DRA_PATH/*$current_date* $local_backup_dir_DRA
expect {
        "password:" {send "$DRA_PASS\r"; exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$DRA_PASS\r";exp_continue}}
        eof
}

#BMS Section
spawn scp root@$BMS_HOST:$BMS_PATH/*$current_date* $local_backup_dir_BMS
expect {
        "password:" {send "$BMS_PASS\r";exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$BMS_PASS\r";exp_continue}}
        eof 
}

#SDB Section
spawn scp root@$SDB_HOST:$SDB_PATH/* $local_backup_dir_SDB
expect {
        "password:" {send "$SDB_PASS\r";exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$SDB_PASS\r";exp_continue}}
        eof 
}

#Switch Section
#Following section first copies the switch config followed by the switch image and bootfiles
spawn scp admin@$SWITCH_HOST:getcfg $local_backup_dir_SWITCH\getcfg-$current_date-$SWITCH_HOST
expect {
        "password:" {send "$SWITCH_PASS\r";exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$SWITCH_PASS\r";exp_continue}}
        eof
}

spawn scp admin@$SWITCH_HOST:getimg1 $local_backup_dir_SWITCH\getimg1-$current_date-$SWITCH_HOST
expect {
        "password:" {send "$SWITCH_PASS\r";exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$SWITCH_PASS\r";exp_continue}}
        eof
}

spawn scp admin@$SWITCH_HOST:getimg2 $local_backup_dir_SWITCH\getimg2-$current_date-$SWITCH_HOST
expect {
        "password:" {send "$SWITCH_PASS\r";exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$SWITCH_PASS\r";exp_continue}}
        eof
}

spawn scp admin@$SWITCH_HOST:getboot $local_backup_dir_SWITCH\getboot-$current_date-$SWITCH_HOST
expect {
        "password:" {send "$SWITCH_PASS\r";exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$SWITCH_PASS\r";exp_continue}}
        eof
}
 





