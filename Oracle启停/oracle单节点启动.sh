#!/bin/bash
# 10.135.66.13

# 切换到oracle用户如果不是
if [ "$USER" != "oracle" ]; then
    echo "Switching to oracle user..."
    su - oracle
    exit
fi

source ~/.bash_profile

start_oracle() {
# 检查数据库状态，启动数据库
db_status=$(ps -ef | grep "$ORACLE_SID$" | grep -v grep | grep -i "ora_smon")
if [ -n "$db_status" ]; then
    echo "Database $ORACLE_SID not closed."
    return
else
    echo "Starting Oracle database..."
    sqlplus / as sysdba <<EOF
    STARTUP;
    EXIT;
EOF
fi

# alert日志检查
while true; do
    log_content=$(tail -n 50 $ORACLE_BASE/diag/rdbms/$ORACLE_SID/$ORACLE_SID/trace/alert_$ORACLE_SID.log)

    if echo "$log_content" | grep -iq "Completed: ALTER DATABASE OPEN"; then
        echo "ORACLE DATABASE OPENED"
        break
    fi

    if echo "$log_content" | grep -iq "error"; then
        echo "error info"
        echo "$log_content" | grep -i "error"
        exit 1
    fi

    # sleep 5s
    sleep 5
done

}

# 多实例检查
if [ -n "$ORACLE_SID" ]; then
    sids=$(grep -oP 'ORACLE_SID=\K[^ ]+' ~/.bash_profile |sort| uniq)
    for sid in $sids
    do 
        export ORACLE_SID=$sid
        echo "Exported ORACLE_SID: $sid"
        start_oracle
    done
else
    echo "ORACLE_SID not set. Please set the ORACLE_SID environment variable."
fi
