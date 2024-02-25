const std = @import("std");
const Elf = std.elf;

pub fn test_elf_parse() !void {
    var file = try std.fs.cwd().openFile("exec", .{});
    defer file.close();
    var buffer: [4096]u8 align(8) = undefined;
    var bytesElf = try file.read(buffer[0..]);
    _ = bytesElf;
    var elfHeader = @ptrCast(*Elf.Elf64_Ehdr, &buffer);
    std.debug.print("{!}\n", .{elfHeader});
}
