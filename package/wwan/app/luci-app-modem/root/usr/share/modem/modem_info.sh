#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"
source "${SCRIPT_DIR}/modem_debug.sh"

#初值化数据结构
init_modem_info()
{
	#基本信息
	name='unknown' 			#名称
	manufacturer='unknown'	#制造商
	revision='-'			#固件版本
	at_port='-'				#AT串口
	mode='unknown'			#拨号模式
	temperature="NaN $(printf "\xc2\xb0")C"	#温度
	update_time='-'			#更新时间

	#SIM卡信息
	sim_status="unknown"	#SIM卡状态
	sim_slot="-"			#SIM卡卡槽
	isp="-"					#运营商（互联网服务提供商）
	sim_number='-'			#SIM卡号码（手机号）
	imei='-'				#IMEI
	imsi='-'				#IMSI
	iccid='-'				#ICCID

	#网络信息
	connect_status="disconnect"	#SIM卡状态
	network_type="-"			#蜂窝网络类型
	cqi_ul="-"					#上行信道质量指示
	cqi_dl="-"					#下行信道质量指示
	ambr_ul="-"					#上行签约速率
	ambr_dl="-"					#下行签约速率
	tx_rate="-"					#上传速率
	rx_rate="-"					#下载速率

	#小区信息
	network_mode="-" #网络模式
	#NR5G-SA模式
	nr_mcc=''
	nr_mnc=''
	nr_duplex_mode=''
	nr_cell_id=''
	nr_physical_cell_id=''
	nr_tac=''
	nr_arfcn=''
	nr_band=''
	nr_dl_bandwidth=''
	nr_rsrp=''
	nr_rsrq=''
	nr_sinr=''
	nr_rxlev=''
	nr_scs=''
	nr_srxlev=''
	#EN-DC模式（LTE）
	endc_lte_mcc=''
	endc_lte_mnc=''
	endc_lte_duplex_mode=''
	endc_lte_cell_id=''
	endc_lte_physical_cell_id=''
	endc_lte_earfcn=''
	endc_lte_freq_band_ind=''
	endc_lte_ul_bandwidth=''
	endc_lte_dl_bandwidth=''
	endc_lte_tac=''
	endc_lte_rsrp=''
	endc_lte_rsrq=''
	endc_lte_rssi=''
	endc_lte_sinr=''
	endc_lte_rxlev=''
	endc_lte_cql=''
	endc_lte_tx_power=''
	endc_lte_srxlev=''
	#EN-DC模式（NR5G-NSA）
	endc_nr_mcc=''
	endc_nr_mnc=''
	endc_nr_physical_cell_id=''
	endc_nr_arfcn=''
	endc_nr_band=''
	endc_nr_dl_bandwidth=''
	endc_nr_rsrp=''
	endc_nr_rsrq=''
	endc_nr_sinr=''
	endc_nr_scs=''
	#LTE模式
	lte_mcc=''
	lte_mnc=''
	lte_duplex_mode=''
	lte_cell_id=''
	lte_physical_cell_id=''
	lte_earfcn=''
	lte_freq_band_ind=''
	lte_ul_bandwidth=''
	lte_dl_bandwidth=''
	lte_tac=''
	lte_rsrp=''
	lte_rsrq=''
	lte_rssi=''
	lte_sinr=''
	lte_rxlev=''
	lte_cql=''
	lte_tx_power=''
	lte_srxlev=''
	#WCDMA模式
	wcdma_mcc=''
	wcdma_mnc=''
	wcdma_lac=''
	wcdma_cell_id=''
	wcdma_uarfcn=''
	wcdma_psc=''
	wcdma_rac=''
	wcdma_rscp=''
	wcdma_ecio=''
	wcdma_phych=''
	wcdma_sf=''
	wcdma_slot=''
	wcdma_speech_code=''
	wcdma_com_mod=''
}

#设置基本信息
set_base_info()
{
	base_info="\"base_info\":{
		\"manufacturer\":\"$manufacturer\",
		\"revision\":\"$revision\",
		\"at_port\":\"$at_port\",
		\"mode\":\"$mode\",
		\"temperature\":\"$temperature\",
		\"update_time\":\"$update_time\"
	},"
}

#设置SIM卡信息
set_sim_info()
{
	if [ "$sim_status" = "ready" ]; then
		sim_info="\"sim_info\":[
			{\"SIM Status\":\"$sim_status\", \"full_name\":\"SIM Status\"},
			{\"ISP\":\"$isp\", \"full_name\":\"Internet Service Provider\"},
			{\"SIM Slot\":\"$sim_slot\", \"full_name\":\"SIM Slot\"},
			{\"SIM Number\":\"$sim_number\", \"full_name\":\"SIM Number\"},
			{\"IMEI\":\"$imei\", \"full_name\":\"International Mobile Equipment Identity\"},
			{\"IMSI\":\"$imsi\", \"full_name\":\"International Mobile Subscriber Identity\"},
			{\"ICCID\":\"$iccid\", \"full_name\":\"Integrate Circuit Card Identity\"}
		],"
	elif [ "$sim_status" = "miss" ]; then
		sim_info="\"sim_info\":[
			{\"SIM Status\":\"$sim_status\", \"full_name\":\"SIM Status\"},
			{\"IMEI\":\"$imei\", \"full_name\":\"International Mobile Equipment Identity\"}
		],"
	elif [ "$sim_status" = "unknown" ]; then
		sim_info="\"sim_info\":[
			{\"SIM Status\":\"$sim_status\", \"full_name\":\"SIM Status\"}
		],"
	else
		sim_info="\"sim_info\":[
			{\"SIM Status\":\"$sim_status\", \"full_name\":\"SIM Status\"},
			{\"SIM Slot\":\"$sim_slot\", \"full_name\":\"SIM Slot\"},
			{\"IMEI\":\"$imei\", \"full_name\":\"International Mobile Equipment Identity\"},
			{\"IMSI\":\"$imsi\", \"full_name\":\"International Mobile Subscriber Identity\"},
			{\"ICCID\":\"$iccid\", \"full_name\":\"Integrate Circuit Card Identity\"}
		],"
	fi
}

#设置网络信息
set_network_info()
{
	network_info="\"network_info\":[
		{\"Network Type\":\"$network_type\", \"full_name\":\"Network Type\"},
		{\"CQI UL\":\"$cqi_ul\", \"full_name\":\"Channel Quality Indicator for Uplink\"},
		{\"CQI DL\":\"$cqi_dl\", \"full_name\":\"Channel Quality Indicator for Downlink\"},
		{\"AMBR UL\":\"$ambr_ul\", \"full_name\":\"Access Maximum Bit Rate for Uplink\"},
		{\"AMBR DL\":\"$ambr_dl\", \"full_name\":\"Access Maximum Bit Rate for Downlink\"},
		{\"Tx Rate\":\"$tx_rate\", \"full_name\":\"Transmit Rate\"},
		{\"Rx Rate\":\"$rx_rate\", \"full_name\":\"Receive Rate\"}
	],"
}

#设置信号信息
set_cell_info()
{
	if [ "$network_mode" = "NR5G-SA Mode" ]; then
		cell_info="\"cell_info\":{
			\"NR5G-SA Mode\":[
				{\"MCC\":\"$nr_mcc\", \"full_name\":\"Mobile Country Code\"},
				{\"MNC\":\"$nr_mnc\", \"full_name\":\"Mobile Network Code\"},
				{\"Duplex Mode\":\"$nr_duplex_mode\", \"full_name\":\"Duplex Mode\"},
				{\"Cell ID\":\"$nr_cell_id\", \"full_name\":\"Cell ID\"},
				{\"Physical Cell ID\":\"$nr_physical_cell_id\", \"full_name\":\"Physical Cell ID\"},
				{\"TAC\":\"$nr_tac\", \"full_name\":\"Tracking area code of cell servedby neighbor Enb\"},
				{\"ARFCN\":\"$nr_arfcn\", \"full_name\":\"Absolute Radio-Frequency Channel Number\"},
				{\"Band\":\"$nr_band\", \"full_name\":\"Band\"},
				{\"DL Bandwidth\":\"$nr_dl_bandwidth\", \"full_name\":\"DL Bandwidth\"},
				{\"RSRP\":\"$nr_rsrp\", \"full_name\":\"Reference Signal Received Power\"},
				{\"RSRQ\":\"$nr_rsrq\", \"full_name\":\"Reference Signal Received Quality\"},
				{\"SINR\":\"$nr_sinr\", \"full_name\":\"Signal to Interference plus Noise Ratio Bandwidth\"},
				{\"RxLev\":\"$nr_rxlev\", \"full_name\":\"Received Signal Level\"},
				{\"SCS\":\"$nr_scs\", \"full_name\":\"SCS\"},
				{\"Srxlev\":\"$nr_srxlev\", \"full_name\":\"Serving Cell Receive Level\"}
			]
		}"
	elif  [ "$network_mode" = "EN-DC Mode" ]; then
		cell_info="\"cell_info\":{
			\"EN-DC Mode\":[
				{\"LTE\":[
						{\"MCC\":\"$endc_lte_mcc\", \"full_name\":\"Mobile Country Code\"},
						{\"MNC\":\"$endc_lte_mnc\", \"full_name\":\"Mobile Network Code\"},
						{\"Duplex Mode\":\"$endc_lte_duplex_mode\", \"full_name\":\"Duplex Mode\"},
						{\"Cell ID\":\"$endc_lte_cell_id\", \"full_name\":\"Cell ID\"},
						{\"Physical Cell ID\":\"$endc_lte_physical_cell_id\", \"full_name\":\"Physical Cell ID\"},
						{\"EARFCN\":\"$endc_lte_earfcn\", \"full_name\":\"E-UTRA Absolute Radio Frequency Channel Number\"},
						{\"Freq band indicator\":\"$endc_lte_freq_band_ind\", \"full_name\":\"Freq band indicator\"},
						{\"Band\":\"$endc_lte_band\", \"full_name\":\"Band\"},
						{\"UL Bandwidth\":\"$endc_lte_ul_bandwidth\", \"full_name\":\"UL Bandwidth\"},
						{\"DL Bandwidth\":\"$endc_lte_dl_bandwidth\", \"full_name\":\"DL Bandwidth\"},
						{\"TAC\":\"$endc_lte_tac\", \"full_name\":\"Tracking area code of cell servedby neighbor Enb\"},
						{\"RSRP\":\"$endc_lte_rsrp\", \"full_name\":\"Reference Signal Received Power\"},
						{\"RSRQ\":\"$endc_lte_rsrq\", \"full_name\":\"Reference Signal Received Quality\"},
						{\"RSSI\":\"$endc_lte_rssi\", \"full_name\":\"Received Signal Strength Indicator\"},
						{\"SINR\":\"$endc_lte_sinr\", \"full_name\":\"Signal to Interference plus Noise Ratio Bandwidth\"},
						{\"RxLev\":\"$endc_lte_rxlev\", \"full_name\":\"Received Signal Level\"},
						{\"RSSNR\":\"$endc_lte_rssnr\", \"full_name\":\"Radio Signal Strength Noise Ratio\"},
						{\"CQI\":\"$endc_lte_cql\", \"full_name\":\"Channel Quality Indicator\"},
						{\"TX Power\":\"$endc_lte_tx_power\", \"full_name\":\"TX Power\"},
						{\"Srxlev\":\"$endc_lte_srxlev\", \"full_name\":\"Serving Cell Receive Level\"}
					]
				},

				{\"NR5G-NSA\":[
						{\"MCC\":\"$endc_nr_mcc\", \"full_name\":\"Mobile Country Code\"},
						{\"MNC\":\"$endc_nr_mnc\", \"full_name\":\"Mobile Network Code\"},
						{\"Physical Cell ID\":\"$endc_nr_physical_cell_id\", \"full_name\":\"Physical Cell ID\"},
						{\"ARFCN\":\"$endc_nr_arfcn\", \"full_name\":\"Absolute Radio-Frequency Channel Number\"},
						{\"Band\":\"$endc_nr_band\", \"full_name\":\"Band\"},
						{\"DL Bandwidth\":\"$endc_nr_dl_bandwidth\", \"full_name\":\"DL Bandwidth\"},
						{\"RSRP\":\"$endc_nr_rsrp\", \"full_name\":\"Reference Signal Received Power\"},
						{\"RSRQ\":\"$endc_nr_rsrq\", \"full_name\":\"Reference Signal Received Quality\"},
						{\"SINR\":\"$endc_nr_sinr\", \"full_name\":\"Signal to Interference plus Noise Ratio Bandwidth\"},
						{\"SCS\":\"$endc_nr_scs\", \"full_name\":\"SCS\"}
					]
				}
			]
		}"
	elif  [ "$network_mode" = "LTE Mode" ]; then
		cell_info="\"cell_info\":{
			\"LTE Mode\":[
				{\"MCC\":\"$lte_mcc\", \"full_name\":\"Mobile Country Code\"},
				{\"MNC\":\"$lte_mnc\", \"full_name\":\"Mobile Network Code\"},
				{\"Duplex Mode\":\"$lte_duplex_mode\", \"full_name\":\"Duplex Mode\"},
				{\"Cell ID\":\"$lte_cell_id\", \"full_name\":\"Cell ID\"},
				{\"Physical Cell ID\":\"$lte_physical_cell_id\", \"full_name\":\"Physical Cell ID\"},
				{\"EARFCN\":\"$lte_earfcn\", \"full_name\":\"E-UTRA Absolute Radio Frequency Channel Number\"},
				{\"Freq band indicator\":\"$lte_freq_band_ind\", \"full_name\":\"Freq band indicator\"},
				{\"Band\":\"$lte_band\", \"full_name\":\"Band\"},
				{\"UL Bandwidth\":\"$lte_ul_bandwidth\", \"full_name\":\"UL Bandwidth\"},
				{\"DL Bandwidth\":\"$lte_dl_bandwidth\", \"full_name\":\"DL Bandwidth\"},
				{\"TAC\":\"$lte_tac\", \"full_name\":\"Tracking area code of cell servedby neighbor Enb\"},
				{\"RSRP\":\"$lte_rsrp\", \"full_name\":\"Reference Signal Received Power\"},
				{\"RSRQ\":\"$lte_rsrq\", \"full_name\":\"Reference Signal Received Quality\"},
				{\"RSSI\":\"$lte_rssi\", \"full_name\":\"Received Signal Strength Indicator\"},
				{\"SINR\":\"$lte_sinr\", \"full_name\":\"Signal to Interference plus Noise Ratio Bandwidth\"},
				{\"RxLev\":\"$lte_rxlev\", \"full_name\":\"RxLev\"},
				{\"RSSNR\":\"$lte_rssnr\", \"full_name\":\"Radio Signal Strength Noise Ratio\"},
				{\"CQI\":\"$lte_cql\", \"full_name\":\"Channel Quality Indicator\"},
				{\"TX Power\":\"$lte_tx_power\", \"full_name\":\"TX Power\"},
				{\"Srxlev\":\"$lte_srxlev\", \"full_name\":\"Serving Cell Receive Level\"}
			]
		}"
	elif  [ "$network_mode" = "WCDMA Mode" ]; then
		cell_info="\"cell_info\":{
			\"WCDMA Mode\":[
				{\"MCC\":\"$wcdma_mcc\", \"full_name\":\"Mobile Country Code\"},
				{\"MNC\":\"$wcdma_mnc\", \"full_name\":\"Mobile Network Code\"},
				{\"LAC\":\"$wcdma_lac\", \"full_name\":\"Location Area Code\"},
				{\"Cell ID\":\"$wcdma_cell_id\", \"full_name\":\"Cell ID\"},
				{\"UARFCN\":\"$wcdma_uarfcn\", \"full_name\":\"UTRA Absolute Radio Frequency Channel Number\"},
				{\"PSC\":\"$wcdma_psc\", \"full_name\":\"Primary Scrambling Code\"},
				{\"RAC\":\"$wcdma_rac\", \"full_name\":\"Routing Area Code\"},
				{\"Band\":\"$wcdma_band\", \"full_name\":\"Band\"},
				{\"RSCP\":\"$wcdma_rscp\", \"full_name\":\"Received Signal Code Power\"},
				{\"Ec/Io\":\"$wcdma_ecio\", \"full_name\":\"Ec/Io\"},
				{\"Ec/No\":\"$wcdma_ecno\", \"full_name\":\"Ec/No\"},
				{\"Physical Channel\":\"$wcdma_phych\", \"full_name\":\"Physical Channel\"},
				{\"Spreading Factor\":\"$wcdma_sf\", \"full_name\":\"Spreading Factor\"},
				{\"Slot\":\"$wcdma_slot\", \"full_name\":\"Slot\"},
				{\"Speech Code\":\"$wcdma_speech_code\", \"full_name\":\"Speech Code\"},
				{\"Compression Mode\":\"$wcdma_com_mod\", \"full_name\":\"Compression Mode\"},
				{\"RxLev\":\"$wcdma_rxlev\", \"full_name\":\"RxLev\"}
			]
		}"
	fi
}

#以Json格式保存模组信息
info_to_json()
{
	base_info="\"base_info\":{},"
	sim_info="\"sim_info\":{},"
	network_info="\"network_info\":{},"
	cell_info="\"cell_info\":{}"
	
	#设置基本信息
	set_base_info

	#判断是否适配
	if [ "$manufacturer" != "unknown" ]; then
		#设置SIM卡信息
		set_sim_info
	fi

	#判断插卡和连接状态
	if [ "$sim_status" = "ready" ] && [ "$connect_status" = "connect" ]; then
		#设置网络信息
		set_network_info
		#设置小区信息
		set_cell_info
    fi

	#拼接所有信息（不要漏掉最后一个}）
	modem_info="{$base_info$modem_info$sim_info$network_info$cell_info}"
}
        # echo $ECIO #参考信号接收质量 RSRQ ecio
        # echo $ECIO1 #参考信号接收质量 RSRQ ecio1
        # echo $RSCP #参考信号接收功率 RSRP rscp0
        # echo $RSCP1 #参考信号接收功率 RSRP rscp1
        # echo $SINR #信噪比 SINR  rv["sinr"]

		# #基站信息
        # echo $COPS_MCC #MCC
        # echo $$COPS_MNC #MNC
        # echo $LAC  #eNB ID
        # echo ''  #LAC_NUM
        # echo $RNC #TAC
        # echo '' #RNC_NUM
        # echo $CID
        # echo ''  #CID_NUM
        # echo $LBAND
        # echo $channel
        # echo $PCI
        # echo $MODTYPE
        # echo $QTEMP

#获取模组信息
get_modem_info()
{
	update_time=$(date +"%Y-%m-%d %H:%M:%S")

	debug "检查模组的AT串口"
	#获取模块AT串口
	if [ -z "$at_port" ]; then
		debug "模组没有AT串口"
		return
	fi

	#检查模块状态（是否处于重启，重置，串口异常状态）
    local at_command="ATI"
	local response=$(at ${at_port} ${at_command})
	if [[ "$response" = *"failed"* ]] || [[ "$response" = *"$at_port"* ]]; then
		debug "模组AT串口未就绪"
		return
	fi

    debug "根据模组的制造商获取信息"
	#更多信息获取
	case $manufacturer in
		"quectel") get_quectel_info "${at_port}" "${platform}" "${define_connect}" ;;
		"fibocom") get_fibocom_info "${at_port}" "${platform}" "${define_connect}" ;;
		"meig") get_meig_info "${at_port}" "${platform}" "${define_connect}" ;;
		"simcom") get_simcom_info "${at_port}" "${platform}" "${define_connect}" ;;
		"huawei") get_huawei_info "${at_port}" "${platform}" "${define_connect}" ;;
		*) debug "未适配该模组" ;;
	esac

	#获取更新时间
	update_time=$(date +"%Y-%m-%d %H:%M:%S")
}

#获取模组数据信息
# $1:AT串口
# $2:制造商
# $3:平台
# $4:连接定义
modem_info()
{
	#初值化模组信息
    debug "初值化模组信息"
    init_modem_info
    debug "初值化模组信息完成"

    #获取模组信息
	at_port="$1"
	manufacturer="$2"
	platform="$3"
	define_connect="$4"
	
	debug "获取模组信息"
	get_modem_info
	
    #整合模块信息
    info_to_json
	echo $modem_info
}

modem_info "$1" "$2" "$3" "$4"