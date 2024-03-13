#!/bin/bash
# 10.135.66.13

sids_retrive(){
    # 定义一个函数来从文件中获取ORACLE_SID
    get_sids_from_file() {
        local file=$1
        if [ -f "$file" ]
        then
            sids+=($(grep -oP 'ORACLE_SID=\K[^ ]+' "$file" | sort | uniq))
        fi
    }

    # 检查日志文件是否存在
    if [ ! -f "$logfile" ]
    then
        echo "Error: Previous Logfile for shuntdown operation not found. $logfile "
        touch $logfile
    else
        # 日志文件中查找Oracle SID，并将结果存储到sids变量中
        sids=$(grep "Exported ORACLE_SID for shutdown:" "$logfile" | awk -F'Exported ORACLE_SID for shutdown: ' '{print $2}'|sort|uniq)
    fi

    # 如果sids为空，则从.bash_profile, oracle_env.sh和ora11g_env.sh中获取ORACLE_SID
    if [ -z "${sids[*]}" ]
    then
        get_sids_from_file "~/.bash_profile"
        get_sids_from_file "/home/oracle/oracle_env.sh"
        get_sids_from_file "/home/oracle/ora11g_env.sh"
    fi

    # 如果sids仍然为空，则使用环境变量ORACLE_SID
    if [ -z "${sids[*]}" ]
    then
        echo "no sid found from files"| tee -a "$logfile"
        sids=($(echo "${ORACLE_SID}"))
    fi
}


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

lsnrctl start

# alert日志检查
while true; do
    log_content=$(tail -n 50 $ORACLE_BASE/diag/rdbms/$ORACLE_SID/$ORACLE_SID/trace/alert_$ORACLE_SID.log)

    if echo "$log_content" | grep -iq "Completed: ALTER DATABASE OPEN"; then
        echo "ORACLE DATABASE $ORACLE_SID OPENED AT $(date)"| tee -a $logfile
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

sids_retrive

for sid in $sids
do 
    export ORACLE_SID=$sid
    echo "Exported ORACLE_SID for startup: $sid"| tee -a $logfile
    start_oracle
done
