//! TODO: This will eventually be an interface for rendering the minesweeper game. there will be likely a terminal and OpenGL implementation
//!
//! Possible methods:
//!   - renderBoard
//!   - renderBoardDebug (Shows mines)
//!   - getUserInput (Gets a click, probably wont be used till after open cell is implemented)

const Self = @This();

const GameBoard = @import("game_board.zig");

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    renderBoard: *const fn (ctx: *anyopaque, board: *const GameBoard) anyerror!void,
    renderBoardDebug: *const fn (ctx: *anyopaque, board: *const GameBoard) anyerror!void,
    getUserInput: *const fn (ctx: *anyopaque) anyerror!Action,
};

// TODO: Maybe move to GameBoard struct? Might make more sense
pub const Action = struct {
    row: u32,
    col: u32,
    flag: bool,
};

pub fn renderBoard(self: Self, board: *const GameBoard) anyerror!void {
    self.vtable.renderBoard(self.ptr, board);
}

pub fn renderBoardDebug(self: Self, board: *const GameBoard) anyerror!void {
    self.vtable.renderBoardDebug(self.ptr, board);
}

pub fn getUserInput(self: Self) anyerror!Action {
    return self.vtable.getUserInput(self.ptr);
}
