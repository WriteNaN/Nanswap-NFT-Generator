const std = @import("std");

pub fn padNumberWithZerosWithAlloc(allocator: std.mem.Allocator, number: []const u8, minLength: usize) ![]const u8 {
    //var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //defer arena.deinit();
    //const allocator = arena.allocator();

    const length = number.len;
    

    if (length < minLength) {
        const paddingLength = @as(usize, @intCast(minLength - length));
        var paddedNumber: []u8 = try allocator.alloc(u8, minLength+1); 

        var index: usize = 0;
        while (index < paddingLength) : (index += 1) {
            paddedNumber[index] = '0'; 
        }

        while (index - paddingLength < length) : (index += 1) {
            paddedNumber[index] = number[index - paddingLength];
        }

        paddedNumber[index] = 0;

        return paddedNumber[0..];
    }

    return number;
}
