#!/bin/bash
# 10.135.66.13

stop_oracle() {
# 检查数据库状态，关闭数据库
db_status=$(ps -ef | grep "$ORACLE_SID$" | grep -v grep | grep -i "ora_smon")
if [ -z "$db_status" ]; then
    echo "Database $ORACLE_SID already closed."| tee -a $logfile
    return
else
    echo "Stopping Oracle database..."| tee -a $logfile
    sqlplus / as sysdba <<EOF
    SHUTDOWN IMMEDIATE;
    EXIT;
EOF
fi

while true; do
    log_content=$(tail -n 50 $ORACLE_BASE/diag/rdbms/$ORACLE_SID/$ORACLE_SID/trace/alert_$ORACLE_SID.log)

    if echo "$log_content" | grep -q "Instance shutdown complete"; then
        echo "Oracle Instance $ORACLE_SID shutdown complete at $(date)"| tee -a $logfile
        break
    fi

    if echo "$log_content" | grep -iq "error"; then
        echo "error info:"| tee -a $logfile
        echo "$log_content" | grep -i "error"| tee -a $logfile
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
        echo "ORACLE processes all stoped"| tee -a $logfile
        break
    else
        echo "remained ora process:"| tee -a $logfile
        echo "$process_info"| tee -a $logfile
        {
            # kill remained ora process
            read -p "kill remained oracle process (y/n)? " answer
            case $answer in
            [Yy]* ) echo "$process_info" | awk '{print $2}' | xargs kill -9;;
            * ) echo "Exiting program."; exit;;
            esac
        } 2>&1 | tee -a "$logfile"
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

logfile="$HOME/oracle_automation_shutdown_startup.log"
if [ ! -f "$logfile" ] then
    touch $logfile
fi

# 多实例检查
# 查找所有的ora_smon进程
processes=$(ps -ef | grep ora_smon)

# 检查processes变量是否为空
if [ -z "$processes" ]; then
  echo "No oracle system monitor processes found."| tee -a "$logfile"
  exit 1
else
  # 截取Oracle SID，并将结果存储到sids变量中
  sids=$(echo "$processes" | awk -F'ora_smon_' '{print $2}'| sort| uniq)
  echo "oracle sid detected, $sids" | tee -a "$logfile"
fi

for sid in $sids
do 
    export ORACLE_SID=$sid
    echo "Exported ORACLE_SID for shutdown: $sid"| tee -a "$logfile"
    stop_oracle
done
