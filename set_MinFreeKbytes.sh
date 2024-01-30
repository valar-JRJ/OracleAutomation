# min水位：下的内存是保留给内核使用的；当到达min，会触发内存的direct reclaim
# low水位：比min高一些，当内存可用量小于low的时候，会触发 kswapd回收内存
# high水位：继续睡眠

MIN_FREE_KBYTES_SYSCTL=$(egrep ^vm.min_free_kbytes /usr/lib/sysctl.d/99-ora19c-sysctl.conf | awk '{print $3}')
MIN_FREE_KBYTES_MEMORY=$(cat /proc/sys/vm/min_free_kbytes)
NUMA_NODE_COUNT=$(numactl --hardware | grep available: | awk '{print $2}')
TOTAL_MEMORY_KBYTES=$(free -k | awk '/Mem:/ {print $2}')
NUMA_BASED=$(( $NUMA_NODE_COUNT * 1048576 ))
MEMORY_BASED=$(( $TOTAL_MEMORY_KBYTES / 200 ))

# 检查 MIN_FREE_KBYTES_SYSCTL 是否为空
if [ -z "$MIN_FREE_KBYTES_SYSCTL" ]
then
  echo "MIN_FREE_KBYTES_SYSCTL is empty"
  exit 1
fi

if [[ $NUMA_BASED -ge $MEMORY_BASED ]]
then
	RECOMMEND_VALUE=$NUMA_BASED
else
	RECOMMEND_VALUE=$MEMORY_BASED
fi
OFFSET=$(echo $RECOMMEND_VALUE*.05 | bc | cut -d"." -f1)
LOWER_BOUND=$(echo $RECOMMEND_VALUE-$OFFSET | bc)
UPPER_BOUND=$(echo $RECOMMEND_VALUE+$OFFSET | bc)

# 检查min_free_kbytes是否在范围内
if [[ $MIN_FREE_KBYTES_SYSCTL -ge LOWER_BOUND && $MIN_FREE_KBYTES_SYSCTL -le UPPER_BOUND ]]
then
	SYSCTL_IN_RANGE=YES
else
	SYSCTL_IN_RANGE=NO
fi
#sysctl in range?
if [[ $MIN_FREE_KBYTES_MEMORY -ge LOWER_BOUND && $MIN_FREE_KBYTES_MEMORY -le UPPER_BOUND ]]
then
	MEMORY_IN_RANGE=YES
else
	MEMORY_IN_RANGE=NO
fi

DETAIL=$(
echo -e "Total Memory:       $TOTAL_MEMORY_KBYTES";
echo -e "NUMA node count:    $NUMA_NODE_COUNT";
echo -e "NUMA calculated:    $NUMA_BASED";
echo -e "memory calculated:  $MEMORY_BASED";
echo -e "recommended value:  $RECOMMEND_VALUE";
echo -e "permitted range:    $LOWER_BOUND to $UPPER_BOUND";
echo -e "in sysctl.conf:     $MIN_FREE_KBYTES_SYSCTL";
echo -e "sysctl in range?:   $SYSCTL_IN_RANGE";
echo -e "in active memory:   $MIN_FREE_KBYTES_MEMORY";
echo -e "memory in range?:   $MEMORY_IN_RANGE";
)

# 计算并设置 vm.min_free_kbytes
# MAX(1GB * number_numa_nodes, 0.5% * total_memory) but smaller than 2GB
# 当系统内存小于32G时，不设置
set_Min_Free_Kbytes() {
	ZZT_V1=$(( $NUMA_NODE_COUNT * 1 * 1024 * 1024 ))
	ZZT_V2=$(( $TOTAL_MEMORY_KBYTES * 5 /10 / 100 ))
	if [ $ZZT_V1 -gt $ZZT_V2 ]
	then
		ZZT_MAX=$ZZT_V1
	else
		ZZT_MAX=$ZZT_V2
	fi
	
	if [ $ZZT_MAX > 2*1024*1024 ]
	then 
		ZZT_MAX = 2*1024*1024
	fi

	ZZT_MAX_GB=$(($ZZT_MAX/1024/1024))
	
	echo ">>> [formula_oracle]vm.min_free_kbytes value (Kb) =MAX(1GB * number_numa_nodes, 0.5% * total_memory) but smaller than 2GB"
	echo ">>> [calculated_zzt]vm.min_free_kbytes = $ZZT_MAX   (About: $ZZT_MAX_GB GB)"
	ZZT_V3=32
	ZZT_V4=$(($TOTAL_MEMORY_KBYTES/1024/1024))
	
	# 内存大于32GB, 设置vm.min_free_kbytes
	if [ $ZZT_V4 -gt $ZZT_V3 ]
	then
		echo ">>> [PASS]The current memory is suitable for setting system parameters."
		echo "Setting vm.min_free_kbytes..."
		sudo sed -i "s/^vm.min_free_kbytes.*/vm.min_free_kbytes = $ZZT_MAX/" /usr/lib/sysctl.d/99-ora19c-sysctl.conf
		sudo sysctl -p /usr/lib/sysctl.d/99-ora19c-sysctl.conf
		echo "vm.min_free_kbytes configured"
	else
	# 内存小于32GB时，从配置文件中删除vm.min_free_kbytes
		echo ">>> [WARN]Your memory is too small to set this parameter."
		sudo sed -i '/^vm.min_free_kbytes/d' /usr/lib/sysctl.d/99-ora19c-sysctl.conf
		sudo sysctl -p /usr/lib/sysctl.d/99-ora19c-sysctl.conf
	fi
	echo -e "Details:\n\n$DETAIL"
}

# 如果在范围内不用修改；
# 如果MIN_FREE_KBYTES_SYSCTL和MIN_FREE_KBYTES_MEMORY均小于可接受范围的最小值，调用函数调整
# 如果MIN_FREE_KBYTES_SYSCTL和MIN_FREE_KBYTES_MEMORY均大于可接受范围的最小值，调用函数调整
# 否则，其他原因导致，退出程序
if [[ $SYSCTL_IN_RANGE = YES && $MEMORY_IN_RANGE = YES ]]
then
	echo -e "SUCCESS: vm.min_free_kbytes is configured as recommended.  Details:\n\n$DETAIL"
elif [[ $MIN_FREE_KBYTES_SYSCTL -lt $LOWER_BOUND || $MIN_FREE_KBYTES_MEMORY -lt $LOWER_BOUND ]]
then
	echo -e ":: Result : 【FAILURE】: vm.min_free_kbytes is not configured as recommended"
	set_Min_Free_Kbytes
elif  [[ $MIN_FREE_KBYTES_SYSCTL -gt $UPPER_BOUND && $MIN_FREE_KBYTES_MEMORY -gt $UPPER_BOUND ]]
then
  	echo -e "WARNING: vm.min_free_kbytes is not configured as recommended.  Details:\n\n$DETAIL"
	set_Min_Free_Kbytes
else
  	echo -e "ERROR: Inconsistent results.  Details:\n\n$DETAILS"
	exit 1
fi