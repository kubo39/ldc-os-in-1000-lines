extern (C):

import common;

void main()
{
    while(true)
    {
prompt:
        printf("> ");
        char[12] cmdline;
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

        if (strcmp(cmdline.ptr, "hello".ptr) == 0)
        {
            printf("Hello, World from shell!\n");
        }
        else if (strcmp(cmdline.ptr, "exit".ptr) == 0)
        {
            exit();
        }
        else if (strcmp(cmdline.ptr, "readfile".ptr) == 0)
        {
            char[128] buf;
            int len = readfile("hello.txt".ptr, buf.ptr, buf.length);
            buf[len] = '\0';
            printf("%s\n", buf.ptr);
        }
        else if (strcmp(cmdline.ptr, "writefile".ptr) == 0)
        {
            writefile("hello.txt".ptr, "Hello from shell!\n".ptr, 19);
        }
        else
        {
            printf("unknown command: %s\n", cmdline.ptr);
        }
    }
}
