const std = @import("std");
const elf = @import("elf.zig");
const ArrayList = std.ArrayList;
const Elf = std.elf;
const heap_allocator = std.heap.page_allocator;
const c = @cImport({
    @cInclude("sys/ptrace.h");
    @cInclude("sys/wait.h");
    @cInclude("sys/user.h");
    @cInclude("unistd.h");
});

pub fn main() anyerror!void {
    try elf.testElfParse();
}

pub fn test_bs() !void {
    var arrayList = std.ArrayList(i32).init(heap_allocator);
    try arrayList.append(1);
    try arrayList.append(2);
    try arrayList.append(3);
    std.debug.print("{?}\n", .{binary_search(arrayList, 69)});
}

pub fn binary_search(arr: ArrayList(i32), target: i32) ?usize {
    var s: usize = 0;
    var e: usize = arr.items.len - 1;
    while (s <= e) {
        const m: usize = s + (e - s) / 2;
        if (arr.items[m] == target) {
            return m;
        } else if (arr.items[m] > target) {
            e = m - 1;
        } else {
            s = m + 1;
        }
    }
    return null;
}

pub fn test_ptrace() !void {
    const cmd = "echo Hello";
    const pid = c.fork();
    if (pid == 0) {
        _ = c.ptrace(c.PTRACE_TRACEME, @as(u32, 0), c.NULL, c.NULL);
        _ = c.execl("/usr/bin/echo", "/usr/bin/echo", cmd, c.NULL);
    } else {
        var status: i32 = 0;
        _ = c.waitpid(pid, &status, 0);
        while (true) {
            _ = c.ptrace(c.PTRACE_SINGLESTEP, pid, c.NULL, c.NULL);
            _ = c.waitpid(pid, &status, 0);
            if (c.WIFEXITED(status)) {
                break;
            }
            var regs: c.user_regs_struct = undefined;
            _ = c.ptrace(c.PTRACE_GETREGS, pid, c.NULL, &regs);
            if (regs.rax == 1) {
                std.debug.print("rax: {}\n", .{regs.rax});
                std.debug.print("rdi: {}\n", .{regs.rdi});
                std.debug.print("rsi: {}\n", .{regs.rsi});
                std.debug.print("rdx: {}\n", .{regs.rdx});
            }
        }
    }
}
