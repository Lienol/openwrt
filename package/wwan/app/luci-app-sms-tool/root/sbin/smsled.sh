#!/bin/sh
# Copyright 2020-2021 Rafał Wabik (IceG) - From eko.one.pl forum
# Licensed to the GNU General Public License v3.0.

	DEV=$(uci -q get sms_tool.general.readport)
	LEDX=$(uci -q get sms_tool.general.smsled)
	MEM=$(uci -q get sms_tool.general.storage)
	STX=$(sms_tool -s $MEM -d $DEV status | cut -c23-27)
	SMS=$(echo $STX | tr -dc '0-9')
	SMSC=$(cat /etc/config/sms_count)
	LEDT="/sys/class/leds/$LEDX/trigger"
	LEDON="/sys/class/leds/$LEDX/delay_on"
	LEDOFF="/sys/class/leds/$LEDX/delay_off"
	LED="/sys/class/leds/$LEDX/brightness"

	LON=$(uci -q get sms_tool.general.ledtimeon)
	TXON=$(echo $LON | tr -dc '0-9')
	TMON=$(($TXON * 1000))

	LOFF=$(uci -q get sms_tool.general.ledtimeoff)
	TXOFF=$(echo $LOFF | tr -dc '0-9')
	TMOFF=$(($TXOFF * 1000))

if [ $SMS == $SMSC ]; then

	exit 0
fi

if [ $SMS > $SMSC ]; then

echo timer > $LEDT
echo $TMOFF > $LEDOFF
echo $TMON > $LEDON
exit 0

fi


exit 0
