#include "array.h"
#include "shellcmd.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char** argv)
{
    char fixture[4096];
    char* command;
    struct array* out = NULL;
    struct array* err = NULL;
    int rc;

    if (argc != 2) {
        return 2;
    }
    snprintf(fixture, sizeof(fixture), "plain ' quote $(touch %s) `touch %s`\nnext line", argv[1], argv[1]);

    command = shellcmd_expr("printf '%%s' %q", fixture);
    if (!command) {
        return 3;
    }
    rc = shellcmd_exec(command, &out, &err);
    free(command);
    if (rc != 0 || !out || out->size != strlen(fixture) || memcmp(out->data, fixture, out->size) != 0) {
        fprintf(stderr, "quoted placeholder did not round-trip path (rc=%d)\n", rc);
        arr_free(out);
        arr_free(err);
        return 4;
    }
    arr_free(out);
    arr_free(err);

    if (access(argv[1], F_OK) == 0) {
        fprintf(stderr, "shell metacharacters executed from path\n");
        return 5;
    }

    command = shellcmd_expr("printf '%%s' %", "legacy path");
    if (!command || strcmp(command, "printf '%s' legacy path") != 0) {
        fprintf(stderr, "legacy %% placeholder behavior changed: %s\n", command ? command : "(null)");
        free(command);
        return 6;
    }
    free(command);

    command = shellcmd_expr("printf '%%s' %q %%", "path");
    if (!command || strcmp(command, "printf '%s' 'path' %") != 0) {
        fprintf(stderr, "escaped %% behavior changed: %s\n", command ? command : "(null)");
        free(command);
        return 7;
    }
    free(command);
    return 0;
}
