#include <stdio.h>

#include "samples.txt"

//signed char samples [] = {0,1};

int main(void)
{
    FILE *file;

	file = fopen("to_flash/sample.bin", "wb");
    fwrite(samples, sizeof(samples), 1, file);
    fclose(file);

    return 0;
}
