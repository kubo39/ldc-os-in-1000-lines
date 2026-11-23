extern (C):

import common;

void main()
{
    while(true)
    {
prompt:
        printf!"> "();
        char[12] cmdline = 0;
        int i = 0;
        for (;; i++)
        {
            char ch = cast(char) getchar();
            putchar(ch);
            if (i == cmdline.sizeof - 1)
            {
                printf!"command line too long\n"();
                goto prompt;
            }
            else if (ch == '\r')
            {
                printf!"\n"();
                cmdline[i] = '\0';
                break;
            }
            else
            {
                cmdline[i] = ch;
            }
        }

        const(char)[] cmd = cmdline[0 .. i];
        if (cmd == "hello")
        {
            printf!"Hello, World from shell!\n"();
        }
        else if (cmd == "exit")
        {
            exit();
        }
        else if (cmd == "readfile")
        {
            char[128] buf = 0;
            int len = readfile("hello.txt".ptr, buf.ptr, buf.length - 1);
            if (len < 0)
            {
                printf!"readfile failed\n"();
                continue;
            }
            buf[len] = '\0';
            printf!"%s\n"(buf.ptr);
        }
        else if (cmd == "writefile")
        {
            writefile("hello.txt".ptr, "Hello from shell!\n".ptr, 19);
        }
        else
        {
            printf!"unknown command: %s\n"(cmd);
        }
    }
}
