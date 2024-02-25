const std = @import("std");
const Elf = std.elf;

pub fn test_elf_parse() !void {
    var file = try std.fs.cwd().openFile("exec", .{});
    defer file.close();
    var buffer: [4096]u8 align(8) = undefined;
    var bytesElf = try file.read(buffer[0..]);
    _ = bytesElf;
    var elfHeader: *Elf.Elf64_Ehdr = @ptrCast(*Elf.Elf64_Ehdr, &buffer);
    std.debug.print("{!}\n", .{elfHeader});
    var bufferCastToOne = @alignCast(1, &buffer);
    var elfSectionHeader = @ptrCast(*Elf.Elf64_Shdr, &bufferCastToOne[elfHeader.e_shoff..]);
    std.debug.print("{!}\n", .{elfSectionHeader});
}
