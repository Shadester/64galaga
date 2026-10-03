/* The rules are psp/game.c itself (the reference): built without floating point, with the flight paths from a table. */
#ifdef RULES_C64   /* the arcade rules (the default) have their own paths (psp/arcade_data.h) */
#define GAME_PATHS_TABLE "paths_table.h"
#endif
#include "../../psp/game.c"
