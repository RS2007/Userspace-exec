const elf = @import("elf.zig");

pub fn main() anyerror!void {
    try elf.testElfParse();
}
