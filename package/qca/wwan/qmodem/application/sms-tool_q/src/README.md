SMS Tool for 3G/4G/5G modem
===================

* sms tool for various of 3g/4g modem
* read sms as raw pdu or decoded text
* support ucs2 decoding

Usage:
----------------

    usage: [options] send phoneNumber message
	    [options] recv
	    [options] delete msg_index | all
	    [options] status
	    [options] ussd code
	    [options] at command
    options:
	    -b <baudrate> (default: 115200)
	    -d <tty device> (default: /dev/ttyUSB0)
	    -D debug (for ussd)
	    -f <date/time format> (for sms/recv)
	    -j json output (for sms/recv)
	    -R use raw input (for ussd)
	    -r use raw output (for ussd and sms/recv)
	    -s <preferred storage> (for sms/recv/status)
