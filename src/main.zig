const std = @import("std");
const cli = @import("cli/main.zig");
const generate = @import("generate.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var config = struct {
    file: []const u8 = undefined,
    dir: []const u8 = undefined,
    out: []const u8 = undefined,
    zip: bool = false,
    number: i32 = undefined
}{};

var input = cli.Option{
    .long_name = "input",
    .short_alias = 'i',
    .help = "Main JSON file with config",
    .required = true,
    .value_ref = cli.mkRef(&config.file),
};

var outDir = cli.Option{
    .long_name = "out",
    .required = true,
    .short_alias = 'o',
    .help = "Out directory, this will be <out>.zip instead if zip is added to args. to prevent OOM error, will be temp moved to disk.",
    .value_ref = cli.mkRef(&config.out)
};

var zip = cli.Option{
    .long_name = "zip",
    .short_alias = 'z',
    .help = "Wheter to zip file when exporting.",
    .required = false,
    .value_ref = cli.mkRef(&config.zip)
};

var num = cli.Option{
    .long_name = "number",
    .short_alias = 'n',
    .help = "Number of NFTs to generate.",
    .required = true,
    .value_ref = cli.mkRef(&config.number)
};

var app = &cli.App{
    .command = cli.Command{
        .name = "generate",
        .options = &.{ &input, &zip, &outDir, &num },
        .target = cli.CommandTarget{
            .action = cli.CommandAction{ .exec = run_cmd },
        },
    },
    .author = "Write Int",
    .version = "v1"
};

pub fn main() !void {
    return cli.run(app, allocator);
}

fn run_cmd() !void {
    const build_config = generate.BuildConfig{
        .file = config.file,
        .dir = config.dir,
        .out = config.out,
        .zip = config.zip,
        .number = config.number
    };
    try generate.build(build_config);
}