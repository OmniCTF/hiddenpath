#include <stdio.h>
#include <string.h>

/* implemented in dispatch.S, vm.S and say.S */
extern int check1(const char *input);
extern int check2(const char *input);
extern void say(int failed);

static char *ask(const char *prompt, char *buf, size_t n)
{
    printf("%s", prompt);
    if (!fgets(buf, (int)n, stdin))
        return NULL;
    buf[strcspn(buf, "\r\n")] = '\0';
    return buf;
}

int main(void)
{
    char buf[64];

    setvbuf(stdout, NULL, _IONBF, 0);

    if (!ask("flag1: ", buf, sizeof(buf)))
        return 1;
    if (check1(buf)) {
        say(1);
        return 1;
    }
    say(0);

    if (!ask("flag2: ", buf, sizeof(buf)))
        return 1;
    if (check2(buf)) {
        say(1);
        return 1;
    }
    say(0);

    return 0;
}
