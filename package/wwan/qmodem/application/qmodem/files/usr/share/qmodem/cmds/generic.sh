#!/bin/sh
# Generic AT command wrappers shared by all vendors.
# Vendor scripts must send AT commands only through cmd_* interfaces
# (here and in cmds/<vendor>.sh) so fixtures can be collected and replayed.
# Convention: $1 is always the AT port, remaining args are command parameters.

#query DNS addresses assigned to a PDP context
#$2: pdp_index
cmd_gtdns()
{
    at "$1" "AT+GTDNS=$2"
}

#query PDP context activation state
cmd_cgact_query()
{
    at "$1" 'AT+CGACT?'
}

#query the address of a PDP context
#$2: pdp_index
cmd_cgpaddr()
{
    at "$1" "AT+CGPADDR=$2"
}

#soft reboot the modem
cmd_cfun_soft_reboot()
{
    at "$1" 'AT+CFUN=1,1'
}

#query SMS storage configuration
cmd_cpms_query()
{
    at "$1" 'AT+CPMS?'
}

#set SMS storage; 2 memories ($2,$3) or 3 memories ($2,$3,$4)
cmd_cpms_set()
{
    if [ $# -ge 4 ]; then
        at "$1" "AT+CPMS=\"$2\",\"$3\",\"$4\""
    else
        at "$1" "AT+CPMS=\"$2\",\"$3\""
    fi
}
