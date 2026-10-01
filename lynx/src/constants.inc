; Memory map, screen geometry and shared limits
SCR_W       = 160
SCR_H       = 102
BUF0        = $a000             ; two 8160-byte frame buffers (code and data end below $a000)
BUF1        = $c000
BUF_FLIP    = (BUF0 ^ BUF1) >> 8
SCB_SIZE    = 15                ; control, flags, collision, next, data, x, y, hsize, vsize
BG_SIZE     = 23                ; background SCB: the same plus the 8-byte pen map
MAX_SCB     = 120
NUM_STARS   = 12
