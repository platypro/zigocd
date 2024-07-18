OUTPUT_FORMAT("elf32-littlearm", "elf32-littlearm", "elf32-littlearm")
OUTPUT_ARCH(arm)
SEARCH_DIR(.)

/* Memory Spaces Definitions */
MEMORY
{
  rom      (rx)  : ORIGIN = 0x00000000, LENGTH = 0x00080000 /* 512kb */
  ram      (rwx) : ORIGIN = 0x20000000, LENGTH = 0x00030000 /* 192kb */
}

/* Section Definitions */
SECTIONS
{
    /* Stack unroll information */
    .ARM.exidx : {
        *(.ARM.exidx)
    } >rom

    /* Compiler information */
    .ARM.attributes (NOLOAD) : {
        *(.ARM.attributes)
    }

    /* Code data */
    .text : {
        . = ALIGN(4);
        *(.text)
        *(.text*)
        *(.rodata)
        *(.rodata*)
    } >rom

    .bss (NOLOAD) : {
        _bss_begin = .;
        *(.bss)
        _bss_end = .;
    } >ram

    .data : {
        _data_load_begin = LOADADDR(.data);
        _data_begin = .;
        *(.data)
        *(.data*)
        _data_end = .;
    } >ram AT>rom
}
