#!/bin/bash
# 10.135.66.13

# 切换到oracle用户如果不是
if [ "$USER" != "oracle" ]; then
    echo "Switching to oracle user..."
    su - oracle
    exit
fi

source ~/.bash_profile

stop_oracle() {

#  检查数据库状态，关闭数据库
db_status=$(ps -ef | grep "$ORACLE_SID$" | grep -v grep | grep -i "ora_smon")
if [ -z "$db_status" ]; then
    echo "Database $ORACLE_SID already closed."
    return
else
    echo "Stopping Oracle database..."
    sqlplus / as sysdba <<EOF
    SHUTDOWN IMMEDIATE;
    EXIT;
EOF
fi

while true; do
    log_content=$(tail -n 50 $ORACLE_BASE/diag/rdbms/$ORACLE_SID/$ORACLE_SID/trace/alert_$ORACLE_SID.log)

    if echo "$log_content" | grep -q "Instance shutdown complete"; then
        echo "Oracle Instance shutdown complete"
        break
    fi

    if echo "$log_content" | grep -iq "error"; then
        echo "error info:"
        echo "$log_content" | grep -i "error"
        exit 1
    fi

    # sleep 5s
    sleep 5
done

# 检查是否还有该实例下的ora进程
while true; do
    process_info=$(ps -ef | grep "$ORACLE_SID$" | grep -v grep | grep -i "ora_")

    # if no ora process left
    if [ -z "$process_info" ]; then
        echo "ORACLE processes all stoped"
        break
    else
        echo "remained ora process:"
        echo "$process_info"

        # kill remained ora process
        read -p "kill remained oracle process (y/n)? " answer
        case $answer in
            [Yy]* ) echo "$process_info" | awk '{print $2}' | xargs kill -9;;
            * ) echo "Exiting program."; exit;;
        esac
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
        stop_oracle
    done
else
    echo "ORACLE_SID not set. Please set the ORACLE_SID environment variable."
fi
