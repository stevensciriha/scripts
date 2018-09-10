#!/usr/bin/expect -f

set timeout 90
set pass "labbws"
set done 0
set local_backup_dir "/stage/"
set PCRF_PASS "labbws"
set PCRF_PATH "/opt/bpc/backup/TARFILE"
set DRA_PASS "labbws"
set DRA_PATH "/opt/bpc/backup/TARFILE"
set BMS_PASS "labbws"
set BMS_PATH "/opt/bwc/backup/TARFILE"
set SDB_PASS "labbws"
set SDB_PATH "/u01/app/oracle/widespan/backups/daily"
# trick to pass in command-line args to spawn
#eval spawn scp $argv

#PCRF Section
spawn scp root@kll5029:$PCRF_PATH/*.tar $local_backup_dir
expect {
        "password:" {send "$PCRF_PASS\r"; exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$PCRF_PASS\r"; exp_continue}}
        eof 
}


#DRA Section
spawn scp root@kll0057:$DRA_PATH/*.tar $local_backup_dir
expect {
        "password:" {send "$DRA_PASS\r"; exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$DRA_PASS\r";exp_continue}}
        eof
}

#BMS Section
spawn scp root@kll5033:$BMS_PATH/*.tar $local_backup_dir
expect {
        "password:" {send "$BMS_PASS\r";exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$BMS_PASS\r";exp_continue}}
        eof 
}

#SDB Section
spawn scp root@kll5030:$SDB_PATH/* $local_backup_dir
expect {
        "password:" {send "$SDB_PASS\r";exp_continue}
        "yes/no)?" {send "yes\r"; expect "password:" {send "$SDB_PASS\r";exp_continue}}
        eof 
}







