const std = @import("std");
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const source_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    source_module.addOptions("config", comptimeBoardOptions(b, source_module));

    const exe = b.addExecutable(.{
        .name = "multi-minesweeper",
        .root_module = source_module,
    });
    runStep(b, exe);

    b.installArtifact(exe);
}

fn comptimeBoardOptions(b: *std.Build, source_module: *std.Build.Module) *Step.Options {
    const width = b.option(u32, "width", "Board width, for comptime argument boards");
    const height = b.option(u32, "height", "Board heigh, for comptime argument boardst");
    const numMines = b.option(u32, "numMines", "Number of mines, for comptime argument boardss");
    const boardFile = b.option([]const u8, "boardFile", "File to build the minesweeper board from");

    const options = b.addOptions();

    options.addOption(?u32, "width", width);
    options.addOption(?u32, "height", height);
    options.addOption(?u32, "numMines", numMines);
    options.addOption(?[]const u8, "boardFile", boardFile);

    // Anonymous import for board file so that passed file can live anywhere on the system
    if (boardFile) |path| {
        const fileLazyPath: std.Build.LazyPath = .{ .cwd_relative = path };
        source_module.addAnonymousImport("board_file", .{ .root_source_file = fileLazyPath });
    }

    return options;
}

fn runStep(b: *std.Build, exe: *Step.Compile) void {
    const runArtifactStep = b.addRunArtifact(exe);
    const runStepArg = b.step("run", "build and run as well");

    runStepArg.dependOn(&runArtifactStep.step);
}
