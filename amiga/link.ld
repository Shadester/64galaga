/* The game is loaded to 0x1000 (src/boot.s) and runs there. Chip RAM is all there is: no OS, no relocation. */
ENTRY(_start)
SECTIONS {
  . = 0x1000;
  .text : { *(.text.start) *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  _data_end = .;
  .bss (NOLOAD) : { _bss_start = .; *(.bss .bss.* COMMON) . = ALIGN(4); _bss_end = .; }
}
