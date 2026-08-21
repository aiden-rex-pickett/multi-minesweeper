const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fixed = b.option(bool, "fixed", "Construct board at compile time with =true") orelse false;

    const width = b.option(u32, "width", "Board Width if using -Dfixed");
    const height = b.option(u32, "height", "Board Height if using -Dfixed");
    const num_mines = b.option(u32, "num_mines", "Number of mines if using -Dfixed");

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

    const exe = b.addExecutable(.{
        .name = "multi-minesweeper",
        .root_module = source_module,
    });

    exe.root_module.addOptions("config", options);

    b.installArtifact(exe);
}
