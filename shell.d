extern (C):

void main()
{
    *(cast(int*) 0x80200000) = 0x1234;
    for (;;) {}
}
