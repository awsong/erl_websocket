#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void mask(unsigned char *key, unsigned char *data, unsigned long len)
{
    unsigned int *p = (unsigned int *)data;
    unsigned int *k = (unsigned int *)key;
    for(int i=4; i<len; i+=4)
    {
	*(p+(i-4)/4) ^= *k;
    }

    int r = len % 4;
    if (r)
    {
	for(int i=0; i<r; i++)
	{
	    data[len-r+i] ^= key[i];
	}
    }
}

int main()
{
    unsigned char keyb[] = {0x37,0xfa,0x21,0x3d};

    /*
    unsigned char t[] = "Hello";
    mask(keyb, t, strlen(t));
    for(int i=0; i<strlen(t); i++)
    {
	printf("0x%02x ", t[i]);
    }
    printf("\n");
    */
    int max = 1024*1024*8;
    int step = 1024*512;
    return 0;
}
