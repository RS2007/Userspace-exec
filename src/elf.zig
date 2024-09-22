const std = @import("std");
const Elf = std.elf;

const PROT_READ = std.os.linux.PROT.READ;
const PROT_EXEC = std.os.linux.PROT.EXEC;
const PROT_WRITE = std.os.linux.PROT.WRITE;

fn roundToNextPage(n: usize) usize {
    return (@divFloor(n, std.mem.page_size) + 1) * std.mem.page_size;
}

pub fn testElfParse() !void {
    var file = try std.fs.cwd().openFile("add3.o", .{});
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
    const symtab = getSection(sectionHeaders, sectionHeaderStringTable, ".symtab", &buffer).?;
    const strtab = getSection(sectionHeaders, sectionHeaderStringTable, ".strtab", &buffer).?;
    const text = getSection(sectionHeaders, sectionHeaderStringTable, ".text", &buffer).?;
    const dataSec = getSection(sectionHeaders, sectionHeaderStringTable, ".data", &buffer).?;
    const rodataSec = getSection(sectionHeaders, sectionHeaderStringTable, ".rodata", &buffer).?;
    const code = buffer[text.sh_offset..][0..text.sh_size];
    const data = buffer[dataSec.sh_offset..][0..dataSec.sh_size];
    const rodata = buffer[rodataSec.sh_offset..][0..rodataSec.sh_size];
    var symbolIndx: usize = 0;
    const symbolNumber: usize = @divExact(symtab.sh_size, @sizeOf(Elf.Elf64_Sym));
    var symbols = std.ArrayList(Elf.Elf64_Sym).init(allocator);
    defer symbols.deinit();
    while (symbolIndx < symbolNumber) {
        const symbolEntry: *align(1) const Elf.Elf64_Sym = @ptrCast(buffer[symtab.sh_offset + symbolIndx * symtab.sh_entsize ..][0..symtab.sh_entsize]);
        try symbols.append(symbolEntry.*);
        symbolIndx += 1;
    }
    const get_varSym = getSymbol(symbols, strtab, "get_var", &buffer).?;
    const set_varSym = getSymbol(symbols, strtab, "set_var", &buffer).?;
    const get_helloSym = getSymbol(symbols, strtab, "get_hello", &buffer).?;
    const mmapedCode = @as([*]u8, @ptrCast(@as(*align(4096) anyopaque, (@alignCast(std.c.mmap(null, roundToNextPage(text.sh_size) + roundToNextPage(dataSec.sh_size) + roundToNextPage(rodataSec.sh_size), PROT_READ | PROT_WRITE, std.os.linux.MAP{ .ANONYMOUS = true, .TYPE = std.os.linux.MAP_TYPE.PRIVATE }, -1, 0))))))[0 .. 3 * 4096];

    @memcpy(mmapedCode[0..code.len], code);
    @memcpy(mmapedCode[roundToNextPage(code.len) .. roundToNextPage(code.len) + data.len], data);
    @memcpy(mmapedCode[roundToNextPage(code.len) + roundToNextPage(data.len) .. roundToNextPage(code.len) + roundToNextPage(data.len) + rodata.len], rodata);

    const relocs = try getRelocs(&buffer, sectionHeaders, sectionHeaderStringTable, allocator);

    for (relocs.items) |reloc| {
        const associatedSectionWithSym = symbols.items[reloc.r_sym()].st_shndx;
        const symAddress = switch (associatedSectionWithSym) {
            1 => symbols.items[reloc.r_sym()].st_value,
            3 => roundToNextPage(code.len) + symbols.items[reloc.r_sym()].st_value,
            5 => roundToNextPage(code.len) + roundToNextPage(data.len) + symbols.items[reloc.r_sym()].st_value,
            else => null,
        };
        switch (associatedSectionWithSym) {
            1 => {},
            3 => {
                std.debug.print("3:{d}\n", .{mmapedCode[symAddress.? .. symAddress.? + 4]});
            },
            5 => {
                std.debug.print("5: {s}\n", .{mmapedCode[symAddress.?..]});
            },
            else => {},
        }
        const relAdrToBePatched = mmapedCode[reloc.r_offset..];
        _ = relAdrToBePatched;
        std.log.warn("{any} and {any} \n", .{ associatedSectionWithSym, symAddress });
        switch (reloc.r_type()) {
            4 => {
                const casted: [4]u8 = @bitCast(
                    @as(i32, @intCast(symAddress.?)) - @as(i32, @intCast(reloc.r_offset)) - @as(i32, @intCast(reloc.r_addend)),
                );
                @memcpy(mmapedCode[reloc.r_offset .. reloc.r_offset + 4], &casted);
            },
            2 => {
                const casted: [4]u8 = @bitCast(@as(i32, @intCast(symAddress.?)) + @as(i32, @intCast(reloc.r_addend)) - @as(i32, @intCast(reloc.r_offset)));
                @memcpy(mmapedCode[reloc.r_offset .. reloc.r_offset + 4], &casted);
            },
            else => |typ| {
                std.debug.print("Unhandled type: {}\n", .{typ});
            },
        }
    }

    const backToOpq: *align(4096) anyopaque = @ptrCast(@alignCast(mmapedCode));
    _ = std.c.mprotect(backToOpq, text.sh_size, PROT_READ | PROT_EXEC);
    const castedGetVar: *fn () u32 = @ptrCast(mmapedCode[get_varSym.st_value..]);
    const castedSetVar: *fn (c_int) void = @ptrCast(mmapedCode[set_varSym.st_value..]);
    const castedGetHello: *fn () [*c]const u8 = @ptrCast(mmapedCode[get_helloSym.st_value..]);
    const ans1 = castedGetVar();
    std.debug.print("get_var() = {d}\n", .{ans1});
    castedSetVar(4);
    std.debug.print("get_var() after set_var(4) = {d}\n", .{castedGetVar()});
    std.debug.print("get_hello()  = {s}\n", .{std.mem.span(castedGetHello())});
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
