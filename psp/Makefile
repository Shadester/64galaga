TARGET = pspgalaga
OBJS = main.o game.o

CFLAGS = -O2 -G0 -Wall -Wextra -std=c99 $(EXTRA_CFLAGS)
LIBS = -lpspgu -lpspdisplay -lpspctrl -lpsprtc -lpspaudio -lpspdebug -lm
EXTRA_TARGETS = EBOOT.PBP
PSP_EBOOT_TITLE = PSP Galaga

PSPSDK = $(shell psp-config --pspsdk-path)
include $(PSPSDK)/lib/build.mak

test:
	cc -O1 -g -Wall -Wextra -fsanitize=address,undefined -o test_game.bin tests/test_game.c -lm && ./test_game.bin
