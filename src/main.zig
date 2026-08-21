const std = @import("std");
const config = @import("config");
const print = std.debug.print;
const Io = std.Io;

const GameBoard = @import("game_board.zig");

pub fn main(init: std.process.Init) !void {
    const rng_impl: std.Random.IoSource = .{ .io = init.io };

    var gameBoard: GameBoard = if (config.fixed)
        GameBoard.comptime_init(rng_impl.interface())
    else else_branch: {
        const boardWidth = 15;
        const boardHeight = 15;
        const numMines = 99;

        // WARNING: May need to change this to defer to the heap if stack size becomes an issue
        var buffer: [boardWidth * boardHeight * @sizeOf(GameBoard.Cell) * 2]u8 align(@alignOf(GameBoard.Cell)) = undefined;

        break :else_branch try GameBoard.init(&buffer, boardWidth, boardHeight, numMines, rng_impl.interface());
    };

    gameBoard.printBoard();
    _ = gameBoard.validate_neighbor_counts();
}
