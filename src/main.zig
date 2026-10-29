const std = @import("std");
const print = std.debug.print;
const Io = std.Io;

const config = @import("config");

const GameAllocator = @import("game_allocator.zig");
const GameBoard = @import("game_board.zig");
const GameIo = @import("game_io_interface.zig");
const TerminalGameIo = @import("terminal_game_io.zig");

const BEGINNER_OPTS = .{ .width = 9, .height = 9, .numMines = 10 };
const INTERMEDIATE_OPTS = .{ .width = 16, .height = 16, .numMines = 40 };
const EXPERT_OPTS = .{ .width = 30, .height = 16, .numMines = 99 };
const CUSTOM_OPTS = .{ .width = 40, .height = 20, .numMines = 99 };

const OPTIONS = BEGINNER_OPTS;

pub fn main(init: std.process.Init) !void {
    const rngImpl: std.Random.IoSource = .{ .io = init.io };

    comptime checkComptimeArgs();
    const comptimeInit = config.width != null and config.height != null and config.num_mines != null;

    // Buffer not used if comptime board being used, hence else [0]u8
    const boardSize = OPTIONS.width * OPTIONS.height;
    var buff: if (!comptimeInit) [
        (boardSize * @sizeOf(GameBoard.Cell)) // Space for cells array
        + ((boardSize + (boardSize & 1)) * @sizeOf(u32)) // Space flood-fill stack, and optionally one more u32 to account for alignment
    ]u8 else [0]u8 = undefined;
    var allocImpl = (comptime GameAllocator.getType(comptimeInit)).init(&buff);

    // var allocImpl = std.heap.DebugAllocator(.{}){};
    // defer _ = allocImpl.deinit();

    var gameBoard = try GameBoard.init(allocImpl.allocator(), comptime if (!comptimeInit) OPTIONS.width else config.width.?, comptime if (!comptimeInit) OPTIONS.height else config.height.?, comptime if (!comptimeInit) OPTIONS.numMines else config.num_mines.?, rngImpl.interface());
    defer gameBoard.deinit();

    try runGame(&gameBoard, TerminalGameIo, init.io);
}

fn runGame(gameBoard: *GameBoard, GameIoImpl: anytype, io: std.Io) anyerror!void {
    comptime GameIo.validateGameIo(GameIoImpl);

    gameLoop: while (true) {
        try GameIoImpl.renderBoard(gameBoard);
        const userAction = try GameIoImpl.getUserInput(io);
        if (userAction.flag) {
            // TODO: Fill after flag bitset migration
        } else if (gameBoard.revealCell(userAction.row, userAction.col)) |result| {
            switch (result) {
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
        } else |err| {
            print("MEMORY RAN OUT WHILE REVEALING CELLS, LIKELY DURING FLOOD FILL!!! {}", .{err});
            unreachable;
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
