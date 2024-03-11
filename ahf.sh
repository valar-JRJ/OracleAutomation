#!/bin/bash
if [ "$USER" != "root" ]; then
    echo "This script needs to be executed by root user"
    exit
fi

# 检查exachk和orachk是否存在
exachk_path=$(which exachk)
orachk_path=$(which orachk)

if [[ -n "$exachk_path" ]]; then
    echo "Running exachk..."
    $exachk_path
    return 0
elif [[ -n "$orachk_path" ]]; then
    echo "Running orachk..."
    $orachk_path
    return 0
else
    return 1
fi


run_check
if [[ $? -eq 0 ]]; then
    echo "health check succeeded"
else
    echo "Neither exachk nor orachk found. Downloading and installing..."
    wget  http://10.56.184.82/soft/oracledatabase/AHF-LINUX_v24.2.0.zip
    unzip -q -o AHF-LINUX_v24.2.0.zip -d ./AHF-LINUX_v24
    cd AHF-LINUX_v24
    ORACLE_BASE=$(sudo su - oracle -c 'env' | grep '^ORACLE_BASE=' | cut -d'=' -f2-)
    data_dir="/opt/oracle.ahf/data"
    space_check(){
        # 检查data路径可用空间
        available=$(df $data_dir | tail -1 | awk '{print $4}')
        available_gb=$((available / 1024 / 1024))
        # 检查是否有至少10G的空间
        if [[ $available_gb -ge 5 ]]; then
            echo "data_dir $data_dir "
        else
            echo "There is less than 5G of space available in $data_dir."
            exit 1
        fi
    }
    mkdir -p $data_dir
    ./ahf_setup -ahf_loc /opt -data_dir 
    if [[ $? -eq 0 ]]; then
        run_check
    else
        exit 1 
    fi
fi