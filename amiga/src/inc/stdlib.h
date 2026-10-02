/* The little C library psp/game.c needs (src/libc.c); the cross compiler has no C library. */
#ifndef STDLIB_H
#define STDLIB_H
int rand(void);
void srand(unsigned seed);
static inline int abs(int x) { return x < 0 ? -x : x; }
#endif
