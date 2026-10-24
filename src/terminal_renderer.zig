/// Terminal rendering and input interface for board game
/// TODO: Change to have use decided at comptime instead of thru vtable interface
const Self = @This();

const GameBoard = @import("game_board.zig");
const Renderer = @import("renderer.zig");

const std = @import("std");
const print = std.debug.print;

pub fn renderer(self: *Self) Renderer {
    return .{ .ptr = self, .vtable = &.{
        .renderBoard = renderBoard,
        .renderBoardDebug = renderBoardDebug,
        .getUserInput = getUserInput,
    } };
}

pub fn renderBoard(ctx: *anyopaque, board: *const GameBoard) anyerror!void {
    _ = ctx;
    printBoard(board, printCell);
}

pub fn renderBoardDebug(ctx: *anyopaque, board: *const GameBoard) anyerror!void {
    _ = ctx;
    printBoard(board, printCellDebug);
}

/// TODO: Loops until user provides valid input to terminal
pub fn getUserInput(
    ctx: *anyopaque,
) anyerror!Renderer.Action {
    _ = ctx;
    return Renderer.Action{
        .row = 1,
        .col = 1,
        .flag = true,
    };
}

/// Prints out board using whatever cell print function is given
fn printBoard(board: *const GameBoard, cellPrint: fn (cell: GameBoard.Cell) void) void {
    for (0..board.width) |_| {
        print("----", .{});
    }
    print("\n", .{});
    for (0..board.height) |row| {
        for (0..board.width) |col| {
            const cell = board.getCell(@intCast(row), @intCast(col)).?;
            cellPrint(cell.*);
        }
        print("|\n", .{});
        for (0..board.width) |_| {
            print("----", .{});
        }
        print("\n", .{});
    }
}

/// Prints a single cell
fn printCell(cell: GameBoard.Cell) void {
    if (cell.flagged) {
        print("| ⚑ ", .{});
    } else if (!cell.revealed) {
        print("| █ ", .{});
    } else if (cell.revealed) {
        print("| {} ", .{cell.neighbors});
    }
}

/// Prints a single cell for debug purposes
fn printCellDebug(cell: GameBoard.Cell) void {
    if (cell.mine) {
        print("| ● ", .{});
    } else if (cell.flagged) {
        print("| ⚑ ", .{});
    } else if (cell.revealed) {
        print("| █ ", .{});
    } else if (!cell.revealed) {
        print("| {} ", .{cell.neighbors});
    }
}
