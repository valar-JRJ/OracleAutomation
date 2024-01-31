#!/bin/bash
# 10.135.66.13

# 是否需要考虑启动19c pdb启动
start_oracle() {
# 检查数据库状态，启动数据库
db_status=$(ps -ef | grep "$ORACLE_SID$" | grep -v grep | grep -i "ora_smon")
if [ -n "$db_status" ]; then
    echo "Database $ORACLE_SID not closed."| tee -a $logfile
    return
else
    echo "Starting Oracle database..."| tee -a $logfile
    sqlplus / as sysdba <<EOF
    STARTUP;
    EXIT;
EOF
fi

# alert日志检查
while true; do
    log_content=$(tail -n 50 $ORACLE_BASE/diag/rdbms/$ORACLE_SID/$ORACLE_SID/trace/alert_$ORACLE_SID.log)

    if echo "$log_content" | grep -iq "Completed: ALTER DATABASE OPEN"; then
        echo "ORACLE DATABASE $ORACLE_SID OPENED"| tee -a $logfile
        break
    fi

    if echo "$log_content" | grep -iq "error"; then
        echo "error info"| tee -a $logfile
        echo "$log_content" | grep -i "error"| tee -a $logfile
        exit 1
    fi

    # sleep 5s
    sleep 5
done
}

# 切换到oracle用户如果不是
if [ "$USER" != "oracle" ]; then
    echo "Switching to oracle user..."
    su - oracle
    exit
fi

source ~/.bash_profile

# 多实例检查
logfile="$HOME/oracle_automation_shutdown_startup.log"

# 检查日志文件是否存在
if [ ! -f "$logfile" ]
then
    echo "Error: Logfile $logfile not found."
    # 该情况需考虑从.bash_profile找到所有sids启动
    exit 1
fi

# 日志文件中查找Oracle SID，并将结果存储到sids变量中
sids=$(grep "Exported ORACLE_SID for shutdown:" "$logfile" | awk -F'Exported ORACLE_SID for shutdown: ' '{print $2}'|sort|uniq)

# sids=$(grep -oP 'ORACLE_SID=\K[^ ]+' ~/.bash_profile |sort| uniq)

for sid in $sids
do 
    export ORACLE_SID=$sid
    echo "Exported ORACLE_SID for startup: $sid"| tee -a $logfile
    start_oracle
done
