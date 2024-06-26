const std = @import("std");
const random = @import("random.zig"); // check random.zig to understand recursion.
const utils = @import("Pad.zig");

const c = @cImport({
    @cInclude("stdio.h");
});

// https://discord.com/channels/@me/1042555712083087382/1189950405417906297
pub const StructuredMetaItem = struct {
    // name
    trait_type: []const u8,
    value: []const u8
};

pub const NanswapJSON = struct { name: []const u8, token_id: usize, description: []const u8, attributes: []StructuredMetaItem };

pub const BuildConfig = struct { file: []const u8, dir: []const u8, out: []const u8, zip: bool, number: i32, threads: u64, applyNone: bool, startFrom: u64 };

pub fn build(config: BuildConfig) !void {
    var arenaU = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arenaU.deinit();

    const allocU = arenaU.allocator();

    _ = std.fs.cwd().makeDir(config.out) catch void;

    const cx: usize = @intCast(config.number + 1);
    const max = try std.fmt.allocPrint(allocU, "{}", .{config.number + 1});
    for (config.startFrom..cx) |i| {
        try doTask(config, i, max, config.applyNone);
    }

    // /workspaces/dev/zig-out/bin/nft-generator -i /workspaces/dev/example/collection.json -o /workspaces/dev/dist -n 3
    if (config.zip) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const xDir = try std.fs.cwd().openDir(config.out, .{});
        const outDir = try xDir.realpathAlloc(allocator, ".");

        //std.debug.print("{s}\n", .{outDir});

        // std.Target.Os.Tag;
        var process = std.process.Child.init(&.{ "zip", "-r", "generated", outDir }, allocator);
        _ = try process.spawnAndWait();

        std.debug.print("saved zip to generated.zip!\n", .{});
    }

    try std.process.exit(0);
}

fn doTask(config: BuildConfig, i: usize, max: []u8, applyNone: bool) !void {
    _ = try setX(config.file, config.out, i, max, applyNone);
    _ = c.printf("Progress: %d/%d\n", i, config.number);
}

// the name doesn't mean anything, sorry I couldn't come up with anything else :(
pub fn setX(filePath: []const u8, outdir: []const u8, numb: usize, max: []const u8, applyNone: bool) !void {
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

    var parsed = try std.json.parseFromSlice(struct { name: []const u8, description: []const u8, layers: []struct { layer: i16, name: []const u8, items: []struct { trait: []const u8, asset: []const u8, odds: i16, invalidWith: ?[]const []const u8 = null } } }, allocator, JSON, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const desc = parsed.value.description;

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

    var arenaP = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arenaP.deinit();
    const allocatorP = arena.allocator();

    const numXc = try std.fmt.allocPrint(allocator, "{}", .{numb});

    const hash = try utils.padNumberWithZerosWithAlloc(allocatorP, numXc, max.len);
    //std.debug.print("{s}", .{hash});
    const nft_name = try std.fmt.allocPrint(allocator, "{s} #{s}", .{ parsed.value.name, hash });

    const fileName = try std.fmt.allocPrint(allocator, "{s}/{}.png", .{ outdir, numb });

    var newAttributes = std.ArrayList(StructuredMetaItem).init(allocator);

    if (applyNone) {
        for (attributes.items) |item| {
            if (std.mem.eql(u8, item.value, "None")) {} else {
                try newAttributes.append(item);
            }
        }
    } else {
        for (attributes.items) |item| {
            try newAttributes.append(item);
        }
    }

    const exportJ = NanswapJSON{ .attributes = newAttributes.items, .name = nft_name, .token_id = numb, .description = desc };

    const jsonFilePath = try std.fmt.allocPrint(allocator, "{s}/{}.json", .{ outdir, numb });
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();
    try std.json.stringify(exportJ, .{}, json_string.writer());
    try std.fs.cwd().writeFile2(.{ .data = json_string.items, .sub_path = jsonFilePath });

    //std.debug.print("line: 109 {}\n", .{max});

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
    _ = try child.spawnAndWait();
}