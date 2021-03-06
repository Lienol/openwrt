/*
  Copyright (C) 2020 Derry <destan19@126.com>

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.
*/
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "appfilter_config.h"

app_name_info_t app_name_table[MAX_SUPPORT_APP_NUM];
int g_app_count = 0;
int g_cur_class_num = 0;
char CLASS_NAME_TABLE[MAX_APP_TYPE][MAX_CLASS_NAME_LEN];

char *get_app_name_by_id(int id){
	int i;
	for (i = 0;i < g_app_count; i++){
		if (id == app_name_table[i].id)
			return app_name_table[i].name;
	}
	return "";
}

void init_app_name_table(void){
	int count = 0;
	char line_buf[2048] = {0};

	FILE * fp = fopen("/etc/appfilter/feature.cfg", "r");
	if (!fp){
		printf("open file failed\n");
		return;
	}

	while (fgets(line_buf, sizeof(line_buf), fp)){
		if (strstr(line_buf, "#"))
			continue;
		if (strlen(line_buf) < 10)
			continue;
		if (!strstr(line_buf, ":"))
			continue;
		char *pos1 = strstr(line_buf, ":");
		char app_info_buf[128] = {0};
		int app_id;
		char app_name[64] = {0};
		memset(app_name, 0x0, sizeof(app_name));
		strncpy(app_info_buf, line_buf, pos1 - line_buf);
		sscanf(app_info_buf, "%d %s", &app_id, app_name);
		app_name_table[g_app_count].id = app_id;
		strcpy(app_name_table[g_app_count].name, app_name);
		g_app_count++;
	}
	fclose(fp);
}

void init_app_class_name_table(void){
	char line_buf[2048] = {0};
	int class_id;
	char class_name[64] = {0};
	FILE * fp = fopen("/etc/appfilter/app_class.txt", "r");
	if (!fp){
		printf("open file failed\n");
		return;
	}
	while (fgets(line_buf, sizeof(line_buf), fp)){
		sscanf(line_buf, "%d %s", &class_id, class_name);
		printf("class id = %d, class name = %s\n", class_id, class_name);
		strcpy(CLASS_NAME_TABLE[class_id - 1], class_name);
		g_cur_class_num++;
	}
	fclose(fp);
}