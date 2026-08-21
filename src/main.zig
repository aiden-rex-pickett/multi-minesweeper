const std = @import("std");
const print = std.debug.print;
const Io = std.Io;

const GameBoard = @import("game_board.zig");

pub fn main(init: std.process.Init) !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // const allocator = std.heap.page_allocator;

    // Allocate one page for the whole game, with 2 byte alignment
    const page = try allocator.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), std.heap.page_size_min);
    defer allocator.free(page);

    const boardWidth = 30;
    const boardHeight = 16;
    const numMines = 99;

    const rng_impl: std.Random.IoSource = .{ .io = init.io };

    var gameBoard: GameBoard = try .init(page[0 .. boardWidth * boardHeight * 4], boardWidth, boardHeight, numMines, rng_impl.interface());
    gameBoard.printBoard();
}
