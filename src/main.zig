const std = @import("std");
const config = @import("config");
const print = std.debug.print;
const Io = std.Io;

const GameBoard = @import("game_board.zig");

pub fn main(init: std.process.Init) !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // NOTE: Use in prod:
    // const allocator = std.heap.page_allocator;

    // Allocate one page for the whole game, with 2 byte alignment
    const page = try allocator.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), std.heap.page_size_min);
    defer allocator.free(page);

    const rng_impl: std.Random.IoSource = .{ .io = init.io };

    var gameBoard: GameBoard = if (config.width != null)
        GameBoard.comptime_init(rng_impl.interface())
    else else_branch: {
        const boardWidth = 30;
        const boardHeight = 16;
        const numMines = 99;

        break :else_branch try GameBoard.init(page[0 .. boardWidth * boardHeight * 4], boardWidth, boardHeight, numMines, rng_impl.interface());
    };

    gameBoard.printBoard();
    _ = gameBoard.validate_neighbor_counts();
}
