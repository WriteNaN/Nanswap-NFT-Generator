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
    number: i32 = undefined,
    applyNone: bool = false,
    threads: u64 = 1,
    startFrom: u64 = 1
}{};

var input = cli.Option{
    .long_name = "input",
    .short_alias = 'i',
    .help = "Main JSON file with config",
    .required = true,
    .value_ref = cli.mkRef(&config.file),
};

var applyNone = cli.Option{
    .long_name = "applyNone",
    .short_alias = 'a',
    .help = "Remove traits with key \"None\" from metadata",
    .required = false,
    .value_ref = cli.mkRef(&config.applyNone)
};

var outDir = cli.Option{
    .long_name = "out",
    .required = true,
    .short_alias = 'o',
    .help = "Directory to export",
    .value_ref = cli.mkRef(&config.out)
};

var zip = cli.Option{
    .long_name = "zip",
    .short_alias = 'z',
    .help = "Wheter to zip file when exporting",
    .required = false,
    .value_ref = cli.mkRef(&config.zip)
};

var threads = cli.Option{
    .long_name = "threads",
    .short_alias = 't',
    .help = "Number of threads to leverage for image generation",
    .required = false,
    .value_ref = cli.mkRef(&config.threads)
};

var num = cli.Option{
    .long_name = "number",
    .short_alias = 'n',
    .help = "Number of NFTs to generate",
    .required = true,
    .value_ref = cli.mkRef(&config.number)
};

var startFrom = cli.Option{
    .long_name = "startFrom",
    .short_alias = 'f',
    .help = "If you have 1/1s in your collections, start from a specific number",
    .required = false,
    .value_ref = cli.mkRef(&config.startFrom)
};

var app = &cli.App{
    .command = cli.Command{
        .name = "generate",
        .options = &.{ &input, &zip, &outDir, &num, &threads, &applyNone, &startFrom },
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
        .number = config.number,
        .threads = config.threads,
        .applyNone = config.applyNone,
        .startFrom = config.startFrom
    };

    try generate.build(build_config);
}