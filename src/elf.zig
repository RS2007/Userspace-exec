const std = @import("std");
const Elf = std.elf;

const PROT_READ = std.os.linux.PROT.READ;
const PROT_EXEC = std.os.linux.PROT.EXEC;
const PROT_WRITE = std.os.linux.PROT.WRITE;
const MAP_PRIVATE = std.os.linux.MAP.PRIVATE;
const MAP_ANONYMOUS = std.os.linux.MAP.ANONYMOUS;

pub fn testElfParse() !void {
    var file = try std.fs.cwd().openFile("add.o", .{});
    defer file.close();
    var buffer: [32168]u8 = undefined;
    std.debug.print("Reading add.o file...\n", .{});
    _ = try file.read(&buffer);
    var stream = std.io.fixedBufferStream(&buffer);
    const reader = stream.reader();
    var elfHeader = try reader.readStruct(Elf.Elf64_Ehdr);
    const sectionNumber = elfHeader.e_shnum;
    const shstrndx = elfHeader.e_shstrndx;
    var sectionIndx: usize = 0;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();
    var sectionHeaders = std.ArrayList(Elf.Elf64_Shdr).init(allocator);
    while (sectionIndx < sectionNumber) {
        var shdr = @ptrCast(*align(1) const Elf.Elf64_Shdr, buffer[elfHeader.e_shoff + sectionIndx * elfHeader.e_shentsize ..][0..elfHeader.e_shentsize]);
        var shdrDerefed = shdr.*;
        try sectionHeaders.append(shdrDerefed);
        sectionIndx += 1;
    }
    var sectionHeaderStringTable = sectionHeaders.items[shstrndx];
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
    var code = buffer[text.sh_offset..][0..text.sh_size];
    var symbolIndx: usize = 0;
    const symbolNumber: usize = @divExact(symtab.sh_size, @sizeOf(Elf.Elf64_Sym));
    var symbols = std.ArrayList(Elf.Elf64_Sym).init(allocator);
    defer symbols.deinit();
    while (symbolIndx < symbolNumber) {
        var symbolEntry = @ptrCast(*align(1) const Elf.Elf64_Sym, buffer[symtab.sh_offset + symbolIndx * symtab.sh_entsize ..][0..symtab.sh_entsize]);
        var symbolEntryDerefed = symbolEntry.*;
        try symbols.append(symbolEntryDerefed);
        symbolIndx += 1;
    }
    var mainFnSymbol = getSymbol(symbols, strtab, "add", &buffer).?;
    // std.debug.print("{x}", .{mainFnSymbol.st_value});
    const mmapedCode = try std.os.mmap(null, 4096, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
    @memcpy(mmapedCode[0..text.sh_size], code);
    // std.debug.print("You are the problem: {}\n", .{mmapedCode.len});
    try std.os.mprotect(mmapedCode, PROT_READ | PROT_EXEC);
    // std.debug.print("length of buffer mmapedCode: {}, text.sh_size: {}\n", .{ mmapedCode.len, text.sh_size });
    var pointsToMain = @alignCast(4096, mmapedCode[mainFnSymbol.st_value..]);
    var toCall = @ptrCast(*fn (c_int, c_int) callconv(.C) c_int, pointsToMain);
    std.debug.print("add({},{}) = {}\n", .{ 2, 3, toCall(2, 3) });
}

pub fn getSymbol(symbolList: std.ArrayList(Elf.Elf64_Sym), strtab: Elf.Elf64_Shdr, symbolName: []const u8, buffer: []u8) ?Elf.Elf64_Sym {
    var index: usize = 0;
    while (index < symbolList.items.len) {
        var currentSymbol = symbolList.items[index];
        var currentSymbolName = buffer[strtab.sh_offset..][currentSymbol.st_name..];
        const zero = [_]u8{0};
        var terminationIndex = std.mem.indexOf(u8, currentSymbolName, &zero).?;
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
        var currentSection = sectionsList.items[index];
        var currentSectionName = buffer[shstrtab.sh_offset..][currentSection.sh_name..];
        const zero = [_]u8{0};
        var terminationIndex = std.mem.indexOf(u8, currentSectionName, &zero).?;
        if (std.mem.eql(u8, sectionName, currentSectionName[0..terminationIndex])) {
            return currentSection;
        }
        index += 1;
    }
    return null;
}
