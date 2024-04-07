const std = @import("std");
const random = @import("random.zig"); // check random.zig to understand recursion.

const c = @cImport({
    @cInclude("stdio.h");
});

// https://discord.com/channels/@me/1042555712083087382/1189950405417906297
pub const StructuredMetaItem = struct {
    // name
    trait_type: []const u8,
    value: []const u8,
};

pub const NanswapJSON = struct { customField: []const u8, attributes: []StructuredMetaItem };

pub const BuildConfig = struct { file: []const u8, dir: []const u8, out: []const u8, zip: bool, number: i32 };

pub fn build(config: BuildConfig) !void {
    const cx : usize = @intCast(config.number+1);
    for (1..cx) |i| {
        _ = try setX(config.file, config.out, i, config.number+1);
        _ = c.printf("Progress: %d/%d\n", i, config.number);
    }
    try std.process.exit(0);
}

// the name doesn't mean anything, sorry I couldn't come up with anything else :(
pub fn setX(filePath: []const u8, outdir: []const u8, numb: usize, max: i32) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var file = try std.fs.cwd().openFile(filePath, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;

    var JSON: []const u8 = "";
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        JSON = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ JSON, line });
    }

    //std.debug.print("{s}", .{JSON});

    var parsed = try std.json.parseFromSlice(struct { name: []const u8, layers: []struct { layer: i16, name: []const u8, items: []struct { trait: []const u8, asset: []const u8, odds: i16, invalidWith: []const []const u8 } } }, allocator, JSON, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    var arenaM = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arenaM.deinit();
    const allocatorM = arena.allocator();

    var arenaL = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arenaL.deinit();
    const allocatorL = arena.allocator();

    var attributes = std.ArrayList(StructuredMetaItem).init(allocatorM);
    defer attributes.deinit();

    var imageLayers = std.ArrayList([]const u8).init(allocatorL);

    for (parsed.value.layers) |layer| {
        var list = std.ArrayList(random.Item).init(allocator);
        const trait = layer.name;

        for (layer.items) |item| {
            try list.append(random.Item{ .asset = item.asset, .odds = item.odds, .trait = item.trait, .invalidWith = item.invalidWith });
        }
        const it = try random.pick(list.items, attributes.items);
        try attributes.append(.{ .trait_type = trait, .value = it.trait });

        const layerI: usize = @intCast(layer.layer);

        try imageLayers.insert(layerI, it.asset);
        //const cc = imageLayers.items;
    }

    const itemsX = imageLayers.items;

    const nft_name = try std.fmt.allocPrint(allocator, "{s} #{}", .{parsed.value.name, numb});

    const fileName = try std.fmt.allocPrint(allocator, "{s}/{}.png", .{ outdir, numb });
    const exportJ = NanswapJSON{
        .attributes = attributes.items,
        .customField = nft_name
    };

    const jsonFilePath = try std.fmt.allocPrint(allocator, "{s}/{}.json", .{ outdir, numb });
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();
    try std.json.stringify(exportJ, .{}, json_string.writer());
    try std.fs.cwd().writeFile2(.{.data = json_string.items, .sub_path = jsonFilePath});

    std.debug.print("{}", .{max});

    try overlayImages(itemsX, fileName);
}

// DOWNLOAD: sudo apt install imagemagick
pub fn overlayImages(images: [][]const u8, out: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Build the arguments array
    var args = std.ArrayList([]const u8).init(allocator);
    try args.append("convert");
    for (images) |image| {
        try args.append(image);
    }
    try args.append("-layers");
    try args.append("merge");
    try args.append(out);

    //std.debug.print("{any}", .{args.items});

    var child = std.process.Child.init(args.items, allocator);
    try child.spawn();
}
