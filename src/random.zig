const std = @import("std");
const s = @import("generate.zig"); // check generate.zig to understand recursion.

pub const Item = struct { trait: []const u8, asset: []const u8, odds: i16, invalidWith: ?[]const []const u8 };

pub fn pick(items: []Item, attributes: []s.StructuredMetaItem) !Item {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var validItems = std.ArrayList(Item).init(allocator);
    for (items) |item| {
        var meetsRequirements: bool = true;
        if (item.invalidWith) |invalidWith| {
        for (invalidWith) |only| {
            for (attributes) |attr| {
                const boolx = std.mem.eql(u8, attr.value, only);
                if (boolx) meetsRequirements = false;
            }
        }
    }
    if (meetsRequirements) {
        try validItems.append(item);
    }
    }

    if (validItems.items.len == 0) {
        return Item{ .trait = "No valid item found", .asset = "", .odds = 0, .invalidWith = &.{} };
    }

    var totalOdds: i16 = 0;
    for (validItems.items) |item| {
        totalOdds += item.odds;
    }

    var random = std.rand.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    const randomNumber = random.random().intRangeAtMostBiased(i32, 1, totalOdds);

    var cumulativeOdds: i16 = 0;
    for (validItems.items) |item| {
        cumulativeOdds += item.odds;
        if (randomNumber <= cumulativeOdds) {
            return item;
        }
    }

    // Thou shalt not reach.
    unreachable;
}
