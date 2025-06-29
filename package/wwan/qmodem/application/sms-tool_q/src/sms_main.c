/*
 * 2017 - 2024 Cezary Jackiewicz <cezary@eko.one.pl>
 * 2014 lovewilliam <ztong@vt.edu>
 * sms tool for various of 3G/4G/5G modem
 */
#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>

#include "pdu_lib/pdu.h"

static void usage()
{
	fprintf(stderr,
		"usage: [options] send phoneNumber message\n"
		"       [options] recv\n"
		"       [options] delete msg_index | all\n"
		"       [options] status\n"
		"       [options] ussd code\n"
		"       [options] at command\n"
		"options:\n"
		"\t-b <baudrate> (default: 115200)\n"
		"\t-c coding scheme (for ussd, 0 - 7BIT, 2 - UCS2, default: detect)\n"
		"\t-d <tty device> (default: /dev/ttyUSB0)\n"
		"\t-D debug (for ussd and at)\n"
		"\t-f <date/time format> (for sms/recv)\n"
		"\t-j json output (for sms/recv)\n"
		"\t-R use raw input (for ussd)\n"
		"\t-r use raw output (for ussd and sms/recv)\n"
		"\t-s <preferred storage> (for sms/recv/status)\n"
		);
	exit(2);
}

static struct termios save_tio;
static int port = -1;
static const char* dev = "/dev/ttyUSB0";
static const char* storage = "";
static const char* dateformat = "%D %T";

static void setserial(int baudrate)
{
	struct termios t;
	if (tcgetattr(port, &t) < 0)
		fprintf(stderr,"tcgetattr(%s)\n", dev);

	memmove(&save_tio, &t, sizeof(t));

	cfmakeraw(&t);

	t.c_cflag |=CLOCAL;
	t.c_cflag |=CREAD;

// data bits
	t.c_cflag &=~CSIZE;
	t.c_cflag |= CS8;
// parity
	t.c_cflag &= ~PARENB;
// stop bits
	t.c_cflag &=~CSTOPB;
// flow control
	t.c_cflag &=~CRTSCTS;

	t.c_oflag &=~OPOST;
	t.c_cc[VMIN]=1;

	switch (baudrate)
	{
		case 0:
			break;
		case 4800:
			cfsetspeed(&t, B4800);
			break;
		case 9600:
			cfsetspeed(&t, B9600);
			break;
		case 19200:
			cfsetspeed(&t, B19200);
			break;
		case 38400:
			cfsetspeed(&t, B38400);
			break;
		case 57600:
			cfsetspeed(&t, B57600);
			break;
		case 115200:
			cfsetspeed(&t, B115200);
			break;
		default:
			fprintf(stderr,"Unsupported baudrate: %d\n", baudrate);
	}
	if (tcsetattr(port, TCSANOW, &t) < 0)
	{
		fprintf(stderr,"tcsetattr(%s)\n", dev);
	}
}

static void resetserial()
{
	if (tcsetattr(port, TCSANOW, &save_tio) < 0)
		fprintf(stderr, "failed tcsetattr(%s): %s\n", dev, strerror(errno));
	tcflush(port, TCIOFLUSH);
	close(port);
}

static void timeout(int sig __attribute__((unused)))
{
	fprintf(stderr,"No response from modem.\n");
	exit(2);
}

static int starts_with(const char* prefix, const char* str)
{
	while(*prefix)
	{
		if (*prefix++ != *str++)
		{
			return 0;
		}
	}
	return 1;
}

static int char_to_hex(char c)
{
	if (isdigit(c))
		return c - '0';
	if (islower(c))
		return 10 + c - 'a';
	if (isupper(c))
		return 10 + c - 'A';
	return -1;
}

static void print_json_escape_char(char c1, char c2)
{
	if (c1 == 0x0) {
		if(c2 == '"') printf("\\\"");
		else if(c2 == '\\') printf("\\\\");
		else if(c2 == '\b') printf("\\b");
		else if(c2 == '\n') printf("\\n");
		else if(c2 == '\f') printf("\\f");
		else if(c2 == '\r') printf("\\r");
		else if(c2 == '\t') printf("\\t");
		else if(c2 == '"') printf("\\\"");
		else if(c2 == '/') printf("\\/");
		else if(c2 < ' ') printf("\\u00%02x", c2);
		else printf("%c", c2);
	} else {
		printf("\\u%02x%02x", (unsigned char)c1, (unsigned char)c2);
	}
}

int main(int argc, char* argv[])
{
	int ch;
	int baudrate = 115200;
	int rawinput = 0;
	int rawoutput = 0;
	int jsonoutput = 0;
	int debug = 0;
	int dcs = -1;

	while ((ch = getopt(argc, argv, "b:c:d:Ds:f:jRr")) != -1){
		switch (ch) {
		case 'b': baudrate = atoi(optarg); break;
		case 'c': dcs = atoi(optarg); break;
		case 'd': dev = optarg; break;
		case 'D': debug = 1; break;
		case 's': storage = optarg; break;
		case 'f': dateformat = optarg; break;
		case 'j': jsonoutput = 1; break;
		case 'R': rawinput = 1; break;
		case 'r': rawoutput = 1; break;
		default:
			usage();
		}
	}

	argv += optind; argc -= optind;

	if (argc < 1)
		usage();
	if (!strcmp("send", argv[0]))
	{
		if(argc < 3)
			usage();
		if(strlen(argv[2]) > 160)
			fprintf(stderr,"sms message too long: '%s'\n", argv[2]);
	}else if (!strcmp("delete",argv[0]))
	{
		if(argc < 2)
			usage();
	}else if (!strcmp("recv", argv[0]))
	{
	}else if (!strcmp("status", argv[0]))
	{
	}else if (!strcmp("ussd", argv[0]))
	{
	}else if (!strcmp("at", argv[0]))
	{
		if(argc < 2)
			usage();
	}else
		usage();

	signal(SIGALRM,timeout);

	char cmdstr[100];
	char pdustr[2*SMS_MAX_PDU_LENGTH+4];
	unsigned char pdu[SMS_MAX_PDU_LENGTH];

	// open the port

	port = open(dev, O_RDWR|O_NONBLOCK|O_NOCTTY);
	if (port < 0)
		fprintf(stderr,"open(%s)\n", dev);
	setserial(baudrate);
	atexit(resetserial);

	close(port);
	port = open(dev, O_RDWR|O_NOCTTY);
	if (port < 0)
		fprintf(stderr,"reopen(%s)\n", dev);

	FILE* pf = fdopen(port, "w");
	FILE* pfi = fdopen(port, "r");
	if (!pf || ! pfi)
		fprintf(stderr,"open port failed\n");
	if(setvbuf(pf, NULL, _IOLBF, 0))
	{
		fprintf(stderr, "failed to make serial port linebuffered\n");
	}

	char buf[1024];
	if (!strcmp("send", argv[0]))
	{
		int pdu_len = pdu_encode("", argv[1], argv[2], pdu, sizeof(pdu));
		if (pdu_len < 0)
			fprintf(stderr,"error encoding to PDU: %s \"%s\n", argv[1], argv[2]);

		const int pdu_len_except_smsc = pdu_len - 1 - pdu[0];
		snprintf(cmdstr, sizeof(cmdstr), "AT+CMGS=%d\r\n", pdu_len_except_smsc);

		int i;
		for (i = 0; i < pdu_len; ++i)
			sprintf(pdustr+2*i, "%02X", pdu[i]);
		sprintf(pdustr+2*i, "%c\r\n", 0x1A);   // End PDU mode with Ctrl-Z.

		fputs("AT+CMGF=0\r\n", pf);
		while(fgets(buf, sizeof(buf), pfi)) {
			if(starts_with("OK", buf))
				break;
		}
		fputs(cmdstr, pf);
		sleep(1);
		fputs(pdustr, pf);

		alarm(5);
		errno = 0;

		while(fgets(buf, sizeof(buf), pfi))
		{
			if(starts_with("+CMGS:", buf))
			{
				printf("sms sent sucessfully: %s", buf + 7);
				return 0;
			} else if(starts_with("+CMS ERROR:", buf))
			{
				fprintf(stderr,"sms not sent, code: %s\n", buf + 11);
			} else if(starts_with("ERROR", buf))
			{
				fprintf(stderr,"sms not sent, command error\n");
			} else if(starts_with("OK", buf))
			{
				return 0;
			}
		}
		fprintf(stderr,"reading port\n");
	}

	if (!strcmp("recv", argv[0]))
	{
		alarm(10);
		if (strlen(storage) > 0) {
			fputs("AT+CPMS=\"", pf);
			fputs(storage, pf);
			fputs("\"\r\n", pf);
			while(fgets(buf, sizeof(buf), pfi)) {
				if(starts_with("OK", buf))
					break;
			}
		}
		fputs("AT+CMGF=0\r\n", pf);
		while(fgets(buf, sizeof(buf), pfi)) {
			if(starts_with("OK", buf))
				break;
		}
		fputs("AT+CMGL=4\r\n", pf);
		int idx[1024];
		int count  = 0;
		if(jsonoutput == 1) {
			printf("{\"msg\":[");
		}
		while(fgets(buf, sizeof buf, pfi))
		{
			if(starts_with("OK", buf))
				break;
			if(starts_with("+CMGL:", buf))
			{
				if(sscanf(buf, "+CMGL: %d,", &idx[count]) != 1)
				{
					fprintf(stderr, "unparsable CMGL response: %s\n", buf+7);
					continue;
				}
				if(!fgets(buf, sizeof buf, pfi))
					fprintf(stderr,"reading pdu %d\n", count);

				if(jsonoutput == 1) {
					if (count > 0) {
						printf(",");
					}
					printf("{\"index\":%d,",idx[count]);
				} else {
					printf("MSG: %d\n",idx[count]);
				}

				++count;

				if(rawoutput == 1)
				{
					if(jsonoutput == 1) {
						printf("\"content\":\"%s\"", buf);
					} else {
						printf("%s\n", buf);
					}
					continue;
				}

				int l = strlen(buf);
				int i;
				for(i = 0; i < l; i+=2)
					pdu[i/2] = 16*char_to_hex(buf[i]) + char_to_hex(buf[i+1]);

				time_t sms_time;
				char phone_str[40];
				char sms_txt[161];

				int tp_dcs_type;
				int ref_number;
				int total_parts;
				int part_number;
				int skip_bytes;

				int sms_len = pdu_decode(pdu, l/2, &sms_time, phone_str, sizeof(phone_str), sms_txt, sizeof(sms_txt),&tp_dcs_type,&ref_number,&total_parts,&part_number,&skip_bytes);
				if (sms_len <= 0) {
					fprintf(stderr, "error decoding pdu %d: %s\n", count-1, buf);
					if(jsonoutput == 1) {
						printf("\"error\":\"error decoding pdu\",\"sender\":\"\",\"timestamp\":\"\",\"content\":\"\"}");
					}
					continue;
				}

				if(jsonoutput == 1) {
					printf("\"sender\":\"%s\",",phone_str);
				} else {
					printf("From: %s\n",phone_str);
				}
				char time_data_str[64];
				strftime(time_data_str, 64, dateformat, gmtime(&sms_time));
				if(jsonoutput == 1) {
					printf("\"timestamp\":\"%s\",",time_data_str);
				} else {
					printf("Date/Time: %s\n",time_data_str);
				}

				if(total_parts > 0) {
					if(jsonoutput == 1) {
						printf("\"reference\":%d,\"part\":%d,\"total\":%d,", ref_number, part_number, total_parts);
					} else {
						printf("Reference number: %d\n", ref_number);
						printf("SMS segment %d of %d\n", part_number, total_parts);
					}
				}

				if(jsonoutput == 1) {
					printf("\"content\":\"");
				}
				switch((tp_dcs_type / 4) % 4)
				{
					case 0:
					{
						// GSM 7 bit
						int i = skip_bytes;
						if(skip_bytes > 0) i = (skip_bytes*8+6)/7;
						for(; i<sms_len; i++)
						{
							if(jsonoutput == 1) {
								print_json_escape_char(0x0, sms_txt[i]);
							} else {
								printf("%c", sms_txt[i]);
							}
						}
						break;
					}
					case 2:
					{
						// UCS2
						for(int i = skip_bytes;i<sms_len;i+=2)
						{
							if(jsonoutput == 1) {
								print_json_escape_char(sms_txt[i],sms_txt[i+1]);
							} else {
								int ucs2_char = 0x000000FF&sms_txt[i+1];
								ucs2_char|=(0x0000FF00&(sms_txt[i]<<8));
								unsigned char utf8_char[5];
								int len = ucs2_to_utf8(ucs2_char,utf8_char);
								int j;
								for(j=0;j<len;j++)
								{
									printf("%c", utf8_char[j]);
								}
							}
						}
						break;
					}
					default:
						break;
				}
				if(jsonoutput == 1) {
					printf("\"}");
				} else {
					printf("\n\n");
				}
			}
		}
		if(jsonoutput == 1) {
			printf("]}\n");
		}

	}

	if (!strcmp("delete",argv[0]))
	{
		int i = atoi(argv[1]);
		int j = i;
		if(!strcmp("all",argv[1]))
		{
			i = 0;
			j = 49;
		}
		printf("delete msg from %d to %d\n",i,j);
		for(;i<=j;i++)
		{
			fprintf(pf, "AT+CMGD=%d\r\n", i);
			while(fgets(buf, sizeof buf, pfi))
			{
				if(starts_with("OK", buf))
				{
					printf("Deleted message %d\n", i);
					break;
				}
				if(starts_with("+CMS ERROR:", buf))
				{
					printf("Error deleting message %d: %s\n", i, buf+12);
					break;
				}
			}
		}
	}

	if (!strcmp("status", argv[0]))
	{
		alarm(10);
		if (strlen(storage) > 0) {
			fputs("AT+CPMS=\"", pf);
			fputs(storage, pf);
			fputs("\"\r\n", pf);
			while(fgets(buf, sizeof(buf), pfi)) {
				if(starts_with("OK", buf))
					break;
			}
		}
		fputs("AT+CPMS?\r\n", pf);
		while(fgets(buf, sizeof buf, pfi))
		{
			if(starts_with("+CPMS:", buf))
			{
				char mem1[9];
				int mem1_used, mem1_total;
				if(sscanf(buf, "+CPMS: \"%2s\",%d,%d,", mem1, &mem1_used, &mem1_total) != 3)
				{
					fprintf(stderr, "unparsable CPMS response: %s\n", buf);
					break;
				}
				printf("Storage type: %s, used: %d, total: %d\n", mem1, mem1_used, mem1_total);
				break;
			}
			if(starts_with("OK", buf))
			{
				break;
			}
		}
	}

	if (!strcmp("ussd", argv[0]))
	{
		enum sms_charset {
			SMS_CHARSET_7BIT = 0,
			SMS_CHARSET_8BIT = 1,
			SMS_CHARSET_UCS2 = 2,
		};

		if (rawinput==1)
		{
			snprintf(cmdstr, sizeof(cmdstr), "AT+CUSD=1,\"%s\",15\r\n", argv[1]);
		}
		else
		{
			int pdu_len = EncodePDUMessage(argv[1], strlen(argv[1]), pdu, SMS_MAX_PDU_LENGTH);
			if (pdu_len > 0)
			{
				if (pdu[pdu_len - 1] == 0) {pdu[pdu_len - 1] = 0x1d;}
				for (int i = 0; i < pdu_len; ++i)
					sprintf(pdustr+2*i, "%02X", pdu[i]);
				snprintf(cmdstr, sizeof(cmdstr), "AT+CUSD=1,\"%s\",15\r\n", pdustr);
			}
			else
				fprintf(stderr, "error encoding to PDU: %s\n", argv[1]);
		}
		if (debug == 1)
			printf("debug: %s\n", cmdstr);

		fputs(cmdstr, pf);
		alarm(10);
		char ussd_buf[320];
		char ussd_txt[800];
		int rc, multiline = 0, tp_dcs_type = 0;
		while(fgets(buf, sizeof buf, pfi))
		{
			if(starts_with("OK", buf))
				continue;
			if(starts_with("+CME ERROR:", buf))
			{
				fprintf(stderr, "error: %s\n", buf+12);
				break;
			}
			if(starts_with("+CUSD:", buf))
			{
				if (debug == 1)
					printf("debug: %s\n", buf);

				char tmp[8];
				rc = sscanf(buf, "+CUSD:%7[^\"]\"%[^\"]\",%d", tmp, ussd_buf, &tp_dcs_type);
				if(rc == 2)
				{
					if(rawoutput == 1)
					{
						multiline = 1;
						rc = 3;
					}
				}

				if(rc != 3)
				{
					fprintf(stderr, "unparsable CUSD response: %s\n", buf);
					break;
				}

				if(rawoutput == 1)
				{
					printf("%s", ussd_buf);
					if (multiline == 1)
						continue;
					else
					{
						printf("\n");
						break;
					}
				}

				int l = strlen(ussd_buf);
				for(int i = 0; i < l; i+=2)
					pdu[i/2] = 16*char_to_hex(ussd_buf[i]) + char_to_hex(ussd_buf[i+1]);

				int upper = (tp_dcs_type & 0xf0) >> 4;
				int lower = tp_dcs_type & 0xf;
				int coding = -1;

				if (upper == 0x3 || upper == 0x8 || (upper >= 0xA && upper <= 0xE))
					coding = -1;

				switch (upper)
				{
					case 0:
						coding = SMS_CHARSET_7BIT;
						break;
					case 1:
						if (lower == 0)
							coding = SMS_CHARSET_7BIT;
						if (lower == 1)
							coding = SMS_CHARSET_UCS2;
						break;
					case 2:
						if (lower <= 4)
							coding = SMS_CHARSET_7BIT;
						break;
					case 4:
					case 5:
					case 6:
					case 7:
						if (((tp_dcs_type & 0x0c) >> 2) < 3)
							coding = (enum sms_charset) ((tp_dcs_type & 0x0c) >> 2);
						break;
					case 9:
						if (((tp_dcs_type & 0x0c) >> 2) < 3)
							coding = (enum sms_charset) ((tp_dcs_type & 0x0c) >> 2);
						break;
					case 15:
						if (lower & 0x4 == 0)
							coding = SMS_CHARSET_7BIT;
						break;
				};

				switch(dcs)
				{
					case SMS_CHARSET_7BIT:
					{
						coding = SMS_CHARSET_7BIT;
						break;
					}
					case SMS_CHARSET_UCS2:
					{
						coding = SMS_CHARSET_UCS2;
						break;
					}
				}

				switch(coding)
				{
					case SMS_CHARSET_7BIT:
					{
						// GSM 7 bit
						l = DecodePDUMessage_GSM_7bit(pdu, l/2, ussd_txt, sizeof(ussd_txt));
						if (l > 0) {
							if (l < sizeof(ussd_txt))
								ussd_txt[l] = 0;

							printf("%s\n", ussd_txt);
						} else {
							fprintf(stderr, "error decoding pdu: %s\n", ussd_buf);
						}

						break;
					}
					case SMS_CHARSET_UCS2:
					{
						// UCS2
						// FIXME: interaction with multiline, sample PDUs needed
						int utf_pos = 0;
						for(int i = 0;i+1<l/2;i+=2)
						{
							int ucs2_char = 0x000000FF&pdu[i+1];
							ucs2_char|=(0x0000FF00&(pdu[i]<<8));
							utf_pos += ucs2_to_utf8(ucs2_char,&ussd_txt[utf_pos]);
						}

						if (utf_pos > 0) {
							if (utf_pos < sizeof(ussd_txt))
								ussd_txt[utf_pos] = 0;

							printf("%s\n", ussd_txt);
						} else {
							fprintf(stderr, "error decoding pdu: %s\n", ussd_buf);
						}

						break;
					}
					default:
						fprintf(stderr, "unknown coding scheme: %d\n", tp_dcs_type);
						break;
				}

				break;
			}
			if (multiline == 1)
			{
				rc = sscanf(buf, "%[^\"]\",%d", ussd_buf, &tp_dcs_type);
				if (rc == 1)
				{
					printf("%s", ussd_buf);
				}
				if (rc == 2)
				{
					printf("%s\n", ussd_buf);
					multiline = 0;
					break;
				}
			}
		}
	}

	if (!strcmp("at", argv[0]))
	{
		alarm(5);
		fputs(argv[1], pf);
		fputs("\r\n", pf);

		while(fgets(buf, sizeof(buf), pfi)) {
			if(starts_with("OK", buf)) {
				if (debug == 1)
					printf("%s", buf);
				exit(0);
			}
			if(starts_with("ERROR", buf)) {
				if (debug == 1)
					printf("%s", buf);
				exit(1);
			}
			if(starts_with("COMMAND NOT SUPPORT", buf)) {
				if (debug == 1)
					printf("%s", buf);
				exit(1);
			}
			if(starts_with("+CME ERROR", buf)) {
				if (debug == 1)
					printf("%s", buf);
				exit(1);
			}
			printf("%s", buf);
		}
	}

	exit(0);
}
