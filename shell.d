extern (C):

import common;

void main()
{
    while(true)
    {
prompt:
        printf("> ");
        char[8] cmdline;
        for (int i = 0;; i++)
        {
            char ch = cast(char) getchar();
            putchar(ch);
            if (i == cmdline.sizeof - 1)
            {
                printf("command line too long\n");
                for (;;) {}
                goto prompt;
            }
            else if (ch == '\r')
            {
                printf("\n");
                cmdline[i] = '\0';
                break;
            }
            else
            {
                cmdline[i] = ch;
            }
        }

        if (strcmp(cmdline.ptr, "hello\0".ptr) == 0)
        {
            printf("Hello, World from shell!\n");
        }
        else if (strcmp(cmdline.ptr, "exit\0".ptr) == 0)
        {
            exit();
        }
        else
        {
            printf("unknown command: %s\n", cmdline.ptr);
        }
    }
}
