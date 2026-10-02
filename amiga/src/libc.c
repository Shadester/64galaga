#include <stdlib.h>
#include <string.h>

/* The same generator as thumby/tests/c_trace.c and thumby/Galaga/game.py: the game is the same on every machine */
static unsigned lcg = 1;
int rand(void) { lcg = (lcg * 1103515245u + 12345u) & 0x7fffffffu; return (int)lcg; }
void srand(unsigned seed) { lcg = seed; }

void *memset(void *s, int c, size_t n) {
    unsigned char *p = s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}
void *memcpy(void *d, const void *s, size_t n) {
    unsigned char *p = d;
    const unsigned char *q = s;
    while (n--) *p++ = *q++;
    return d;
}
