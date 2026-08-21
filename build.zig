const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fixed = b.option(bool, "fixed", "Construct board at compile time with =true. Must provide -Dwidth, -Dheight, -Dnum_mines if so") orelse false;

    const width = b.option(u32, "width", "Board Width, only has an effect if using -Dfixed=true");
    const height = b.option(u32, "height", "Board Height, only has an effect if using -Dfixed=true");
    const num_mines = b.option(u32, "num_mines", "Number of mines, only has an effect if using -Dfixed=true");

    const options = b.addOptions();

    options.addOption(?u32, "width", width);
    options.addOption(?u32, "height", height);
    options.addOption(?u32, "num_mines", num_mines);
    options.addOption(bool, "fixed", fixed);

    const source_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    source_module.addOptions("config", options);

    const exe = b.addExecutable(.{
        .name = "multi-minesweeper",
        .root_module = source_module,
    });

    b.installArtifact(exe);
}
