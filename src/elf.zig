const std = @import("std");
const Elf = std.elf;

const PROT_READ = std.os.linux.PROT.READ;
const PROT_EXEC = std.os.linux.PROT.EXEC;
const PROT_WRITE = std.os.linux.PROT.WRITE;

pub fn testElfParse() !void {
    var file = try std.fs.cwd().openFile("add2.o", .{});
    defer file.close();
    var buffer: [32168]u8 = undefined;
    std.debug.print("Reading add.o file...\n", .{});
    _ = try file.read(&buffer);
    var stream = std.io.fixedBufferStream(&buffer);
    const reader = stream.reader();
    const elfHeader = try reader.readStruct(Elf.Elf64_Ehdr);
    const sectionNumber = elfHeader.e_shnum;
    const shstrndx = elfHeader.e_shstrndx;
    var sectionIndx: usize = 0;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var sectionHeaders = std.ArrayList(Elf.Elf64_Shdr).init(allocator);
    while (sectionIndx < sectionNumber) {
        const shdr: *align(1) const Elf.Elf64_Shdr = @ptrCast(buffer[elfHeader.e_shoff + sectionIndx * elfHeader.e_shentsize ..][0..elfHeader.e_shentsize]);
        try sectionHeaders.append(shdr.*);
        sectionIndx += 1;
    }
    const sectionHeaderStringTable = sectionHeaders.items[shstrndx];
    // var sectionStringList = buffer[sectionHeaderStringTable.sh_offset..][0..sectionHeaderStringTable.sh_size];
    // std.debug.print("Header: {any}\n", .{elfHeader});
    // std.debug.print("Section Header num: {}\n", .{sectionNumber});
    // std.debug.print("Section String list: {s}\n", .{sectionStringList});
    const symtab = getSection(sectionHeaders, sectionHeaderStringTable, ".symtab", &buffer).?;
    const strtab = getSection(sectionHeaders, sectionHeaderStringTable, ".strtab", &buffer).?;
    const text = getSection(sectionHeaders, sectionHeaderStringTable, ".text", &buffer).?;
    // std.debug.print("symtab: {any}\n", .{symtab});
    // std.debug.print("strtab: {any}\n", .{strtab});
    // std.debug.print("text: {any}\n", .{text});
    // const symbolTable = buffer[strtab.sh_offset..][0..strtab.sh_size];
    // std.debug.print("symtab: {s}\n", .{symbolTable});
    const code = buffer[text.sh_offset..][0..text.sh_size];
    var symbolIndx: usize = 0;
    const symbolNumber: usize = @divExact(symtab.sh_size, @sizeOf(Elf.Elf64_Sym));
    var symbols = std.ArrayList(Elf.Elf64_Sym).init(allocator);
    defer symbols.deinit();
    while (symbolIndx < symbolNumber) {
        const symbolEntry: *align(1) const Elf.Elf64_Sym = @ptrCast(buffer[symtab.sh_offset + symbolIndx * symtab.sh_entsize ..][0..symtab.sh_entsize]);
        try symbols.append(symbolEntry.*);
        symbolIndx += 1;
    }
    const mainFnSymbol = getSymbol(symbols, strtab, "add3", &buffer).?;
    // std.debug.print("{x}", .{mainFnSymbol.st_value});
    const mmapedCode: *align(4096) [4096]u8 = @ptrCast(@alignCast(std.c.mmap(null, 4096, PROT_READ | PROT_WRITE, std.os.linux.MAP{ .ANONYMOUS = true, .TYPE = std.os.linux.MAP_TYPE.PRIVATE }, -1, 0)));
    //var toWrite = code[0x38..][0..];
    //toWrite = @as([]u8, 0xFFFFFFC4);

    @memcpy(mmapedCode.*[0..text.sh_size], code);
    // std.debug.print("You are the problem: {}\n", .{mmapedCode.len});
    //const relocs = try getRelocs(&buffer, sectionHeaders, sectionHeaderStringTable, allocator);

    const relocs = try getRelocs(&buffer, sectionHeaders, sectionHeaderStringTable, allocator);
    // INFO: relocation happens here
    //const castedToComplement: [4]u8 = @bitCast(@as(i32, @intCast(-0x4c)));
    //@memcpy(mmapedCode.*[mainFnSymbol.st_value + 24 .. mainFnSymbol.st_value + 28], &castedToComplement);
    for (relocs.items) |reloc| {
        switch (reloc.r_type()) {
            4 => {
                const casted: [4]u8 = @bitCast(@as(i32, @intCast((@as(i64, @intCast(sectionHeaders.items[mainFnSymbol.st_shndx].sh_addr))) +
                    @as(i64, @intCast(getSymbol(symbols, strtab, "add2", &buffer).?.st_value)) +
                    -@as(i64, @intCast(reloc.r_offset)) +
                    reloc.r_addend)));
                @memcpy(mmapedCode[reloc.r_offset .. reloc.r_offset + 4], &casted);
            },
            else => {
                std.debug.assert(false);
            },
        }
    }

    const backToOpq: *align(4096) anyopaque = @ptrCast(@alignCast(mmapedCode));
    _ = std.c.mprotect(backToOpq, text.sh_size, PROT_READ | PROT_EXEC);
    // std.debug.print("length of buffer mmapedCode: {}, text.sh_size: {}\n", .{ mmapedCode.len, text.sh_size });
    const casted: *fn (i32, i32, i32) i32 = @ptrCast(mmapedCode[mainFnSymbol.st_value..]);
    std.debug.print("add({},{},{}) = {}\n", .{ 2, 3, 5, casted(2, 3, 5) });
}

pub fn getRelocs(buffer: []u8, sections: std.ArrayList(Elf.Elf64_Shdr), shstrtab: Elf.Elf64_Shdr, allocator: std.mem.Allocator) !std.ArrayList(Elf.Elf64_Rela) {
    var relocIndx: usize = 0;
    const relocSection = getSection(sections, shstrtab, ".rela.text", buffer).?;
    const relocEntryNum = @divExact(relocSection.sh_size, relocSection.sh_entsize);
    var relocEntries = std.ArrayList(Elf.Elf64_Rela).init(allocator);
    while (relocIndx < relocEntryNum) {
        const relocEntry: *align(1) const Elf.Elf64_Rela = @ptrCast(buffer[relocSection.sh_offset + relocIndx * relocSection.sh_entsize ..][0..relocSection.sh_entsize]);
        const relocEntryDerefed = relocEntry.*;
        try relocEntries.append(relocEntryDerefed);
        relocIndx += 1;
    }

    return relocEntries;
}

pub fn getSymbol(symbolList: std.ArrayList(Elf.Elf64_Sym), strtab: Elf.Elf64_Shdr, symbolName: []const u8, buffer: []u8) ?Elf.Elf64_Sym {
    var index: usize = 0;
    while (index < symbolList.items.len) {
        const currentSymbol = symbolList.items[index];
        var currentSymbolName = buffer[strtab.sh_offset..][currentSymbol.st_name..];
        const zero = [_]u8{0};
        const terminationIndex = std.mem.indexOf(u8, currentSymbolName, &zero).?;
        if (std.mem.eql(u8, symbolName, currentSymbolName[0..terminationIndex])) {
            return currentSymbol;
        }
        index += 1;
    }
    return null;
}

pub fn getSection(sectionsList: std.ArrayList(Elf.Elf64_Shdr), shstrtab: Elf.Elf64_Shdr, sectionName: []const u8, buffer: []u8) ?Elf.Elf64_Shdr {
    var index: usize = 0;
    while (index < sectionsList.items.len) {
        const currentSection = sectionsList.items[index];
        var currentSectionName = buffer[shstrtab.sh_offset..][currentSection.sh_name..];
        const zero = [_]u8{0};
        const terminationIndex = std.mem.indexOf(u8, currentSectionName, &zero).?;
        if (std.mem.eql(u8, sectionName, currentSectionName[0..terminationIndex])) {
            return currentSection;
        }
        index += 1;
    }
    return null;
}
