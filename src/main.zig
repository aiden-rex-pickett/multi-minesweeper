const std = @import("std");
const print = std.debug.print;
const Io = std.Io;

const config = @import("config");

const GameAllocator = @import("game_allocator.zig");
const GameBoard = @import("game_board.zig");
const GameIo = @import("game_io_interface.zig");
const TerminalGameIo = @import("terminal_game_io.zig");

// TODO: Optimize buffer allocation to be as small as possible
// Would also require refactoring interface to check on instance instead of type maybe?
pub fn main(init: std.process.Init) !void {
    const rngImpl: std.Random.IoSource = .{ .io = init.io };

    const boardWidth = 4;
    const boardHeight = 4;
    const numMines = 15;

    comptime checkComptimeArgs();
    const comptimeInit = config.width != null and config.height != null and config.num_mines != null;

    // Buffer not used if comptime board being used, hence else [0]u8
    var buff: if (!comptimeInit) [boardWidth * boardHeight * @sizeOf(GameBoard.Cell) + boardWidth * boardHeight * @sizeOf(GameBoard.Pair)]u8 else [0]u8 = undefined;
    var allocImpl = (comptime GameAllocator.getType(comptimeInit)).init(&buff);

    // var allocImpl = std.heap.DebugAllocator(.{}){};
    // defer _ = allocImpl.deinit();

    var gameBoard = try GameBoard.init(allocImpl.allocator(), comptime if (!comptimeInit) boardWidth else config.width.?, comptime if (!comptimeInit) boardHeight else config.height.?, comptime if (!comptimeInit) numMines else config.num_mines.?, rngImpl.interface());
    defer gameBoard.deinit();

    try runGame(&gameBoard, TerminalGameIo, init.io);
}

fn runGame(gameBoard: *GameBoard, GameIoImpl: anytype, io: std.Io) anyerror!void {
    comptime GameIo.validateGameIo(GameIoImpl);

    gameLoop: while (true) {
        try GameIoImpl.renderBoardDebug(gameBoard);
        const userAction = try GameIoImpl.getUserInput(io);
        if (userAction.flag) switch (gameBoard.toggleFlag(userAction.row, userAction.col)) {
            .Invalid => {
                print("FLAG RESULT INVALID\n", .{});
            },
            .Nop => {
                print("FLAG REAULT NOP\n", .{});
            },
            .Safe => {
                print("FLAG RESULT SAFE\n", .{});
            },
        } else switch (gameBoard.revealCell(userAction.row, userAction.col)) {
            .Exploded => {
                print("OH NO. CELL AT {}, {} WAS A MINE!\n", .{ userAction.row, userAction.col });
                break :gameLoop;
            },
            .Win => {
                print("YOU WIN!!!\n", .{});
                break :gameLoop;
            },
            .Safe => {
                print("Okay...\n", .{});
            },
            .Nop => {
                print("That did nothing...\n", .{});
            },
            .Invalid => {
                print("Click a valid cell please\n", .{});
            },
        }
        print("CELLS REMAIN: {}\n", .{gameBoard.cellsLeft});
    }
}

/// This function validates at compile time that the provided compile time arguments are valid
inline fn checkComptimeArgs() void {
    var check: comptime_int = 0;
    if (config.width != null) check += 1;
    if (config.height != null) check += 1;
    if (config.num_mines != null) check += 1;

    if (check == 0) return;

    if (check != 3)
        @compileError("Comptime board initalization attempted without providing all of the following arguments: -Dwidth, -Dheight, and -Dnum_mines arguments");

    if (config.width.? <= 0)
        @compileError("Comptime board initalization attempted with 0 width board, make sure -Dwidth is greater than 0");

    if (config.height.? <= 0)
        @compileError("Comptime board initalization attempted with 0 height board, make sure -Dheight is greater than 0");

    if (config.num_mines.? > config.width.? * config.height.?)
        @compileError("Comptime board initalization arguments invalid, more mines than there are cells. Make sure -Dnum_mines <= -Dwidth * -Dheight");
}
