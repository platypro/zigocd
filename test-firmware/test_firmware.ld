MEMORY
{
  rom      (rx)  : ORIGIN = 0x00000000, LENGTH = 0x00040000
  ram      (rwx) : ORIGIN = 0x20000000, LENGTH = 0x00020000
  bkupram  (rwx) : ORIGIN = 0x47000000, LENGTH = 0x00002000
  qspi     (rwx) : ORIGIN = 0x04000000, LENGTH = 0x01000000
}

SECTIONS
{
    .vector_table 0x00000000 :
    {
        QUAD(_stack_start)
        *(.vector_table)
    }

    .text :
    {
        . = ALIGN(4);
        *(.text)
        *(.text.*)
    } > rom

    .rodata :
    {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
    } > rom

    .bss :
    {
        _bss_start = .;
        *(.bss .bss*)
        _bss_end = .;
    } > ram

    .stack :
    {
        _stack_start = .;
        . = . + 0x8000;
        _stack_end = .;
    } > ram

    .data :
    {
        . = ALIGN(4);
        _data_start = .;
        *(.data)
        *(.data*)
        _data_end = .;
    } > rom AT>ram

    _data_load_start = LOADADDR(.data);

    .ARM.exidx :
    {
        *(.ARM.exidx)
        *(.ARM.exidx*)
    } > rom

    .ARM.extab :
    {
        *(.ARM.extab*)
    } > rom

}
