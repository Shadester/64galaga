/* The hash of src/selftest.h on this Mac (psp/game.c). Flags: -DTICKS=n -DSTART_STAGE=n -DFORCECAPTURE */
#include <stdio.h>

static unsigned lcg = 1;
static int lcg_rand(void) { lcg = (lcg * 1103515245u + 12345u) & 0x7fffffffu; return (int)lcg; }
static void lcg_srand(unsigned s) { lcg = s; }
#define rand lcg_rand
#define srand lcg_srand
#include "../../psp/game.c"
#include "selftest.h"

int main(void) {
    printf("%08x\n", selftest_hash(TICKS));
    return 0;
}
