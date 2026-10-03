/* The rules are psp/game.c itself (the reference): built without floating point, with the flight paths from a table. */
#ifndef RULES_ARCADE   /* the arcade rules have their own paths (psp/arcade_data.h) */
#define GAME_PATHS_TABLE "paths_table.h"
#endif
#include "../../psp/game.c"
