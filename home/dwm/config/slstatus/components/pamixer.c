
// components/pamixer.c
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../util.h"

const char unknown_str[] = "n/a";

const char *
pamixer_status(void)
{
    static char buf[16];
    FILE *fp;
    char line[16];
    int vol;
    int is_muted = 0;

    // 获取静音状态
    fp = popen("pamixer --get-mute", "r");
    if (!fp)
        return unknown_str;
    if (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "true", 4) == 0)
            is_muted = 1;
    }
    pclose(fp);

    // 获取音量
    fp = popen("pamixer --get-volume", "r");
    if (!fp)
        return unknown_str;
    if (!fgets(line, sizeof(line), fp)) {
        pclose(fp);
        return unknown_str;
    }
    pclose(fp);
    vol = atoi(line);

    const char *icon;
    if (is_muted)
        icon = "󰖁";
    else if (vol <= 33)
        icon = "󰕿";
    else if (vol <= 66)
        icon = "󰖀";
    else
        icon = "󰕾";

    esnprintf(buf, sizeof(buf), "%s %d%%", icon, vol);
    return buf;
}

