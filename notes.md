## Notes on the ELF file format

- There are table types:

  1. `.symtab`

  - Table with info about functions

  2. `.strtab`

  - names associated with symbol table entries

  3. `.shstrtab`

  - holds section names

- ELF Header

```
e_ident(16), e_type(2), e_machine(2), e_version(4), e_entry(4), e_phoff(4),
e_shoff(4), e_flags(4), e_ehsize(2), e_phentsize(2), e_phnum(2), e_shentsize(2)
e_shnum(2), e_shstrndx(2)
```

1.  e_ident = elf identifier(first 4 is 0x7F,ELF, then 5 to 7 are parity, rest padding and the final byte is the length of this section which is 0x10 in hex)
2.  e_type = executable/relocatable/shared library
3.  e_machine = number corresponding to the cpu vendor its compiled for
4.  e_version
5.  e_entry = transfer control to this address on execution
6.  e_phoff = program header offset
7.  e_shoff = section header table offset
8.  e_flags = flags.
9.  e_ehsize = size of the ELF header.
10. e_phentsize(2) - size of a program header.
11. e_phnum - number of program headers, which directly corresponds to the number of segments in the file.(like data and text)
12. section headers stuff

- Program header
  - Info on segments
- Section header
  - Info on sections

> Sections are for the linker and segments are for the OS

- Segments

  - The kernel only really cares about three types of program header entries.
  - The first type is the `PT_LOAD` segment, which describes areas of the new program's running memory. This includes code and data sections that come from the executable file, together with the size of a BSS section. The BSS will be filled with zeroes (thus only its length needs to be stored in the executable file).
  - The second entry of interest is a `PT_INTERP` entry, which identifies the run-time linker needed to assemble the complete program.
  - The kernel also gets a single bit of information from a `PT_GNU_STACK` entry, if present, which indicates whether the program's stack should be made executable or not.

- Sections:
  - Sections get loaded as segments later.
  - Section header, gives `sh_offset` to the bytes buffer.
  - The header name string is in `.shstrtab`
  - Using the two we can get the `.text` section from the bytes buffer.
  - To get the memory address of the function that we need to call, the symbols are parsed from `.symtab`.
  - in `.symbtab` functions have the `ST_FUNC` type, the memory address is obtained and that is used to get a pointer to the executable mmaped memory.
  - the function pointer is dereferenced and called to execute the function.
