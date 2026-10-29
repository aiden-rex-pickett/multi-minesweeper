const std = @import("std");
const print = std.debug.print;
const Io = std.Io;

const config = @import("config");

const GameAllocator = @import("game_allocator.zig");
const GameBoard = @import("game_board.zig");
const FlagBitset = @import("flag_bitset.zig");
const GameIo = @import("game_io_interface.zig");
const TerminalGameIo = @import("terminal_game_io.zig");

const BEGINNER_OPTS = .{ .width = 9, .height = 9, .numMines = 10 };
const INTERMEDIATE_OPTS = .{ .width = 16, .height = 16, .numMines = 40 };
const EXPERT_OPTS = .{ .width = 30, .height = 16, .numMines = 99 };
const CUSTOM_OPTS = .{ .width = 3, .height = 3, .numMines = 0 };

const OPTIONS = BEGINNER_OPTS;

pub fn main(init: std.process.Init) !void {
    const rngImpl: std.Random.IoSource = .{ .io = init.io };

    comptime checkComptimeArgs();
    const comptimeInit = config.width != null and config.height != null and config.num_mines != null;

    const numTeams = 1;

    const boardSize = OPTIONS.width * OPTIONS.height;

    const flagBitsetSize = (boardSize / 64 + if (boardSize & 63 != 0) @as(u64, 1) else @as(u64, 0)) * numTeams * 8;
    const floodFillStackSize = boardSize * @sizeOf(u32);
    const cellArraySize = boardSize * @sizeOf(GameBoard.Cell);

    const totalSize = flagBitsetSize + floodFillStackSize + cellArraySize + 8; // 8 more bytes to resolve alignment issues

    // TODO: Main will segfault immediately if stack size too big, so find a way to measure how much we
    // need to allocate and defer to allocating a page from the OS instead in that case
    // (either huge boards or hundreds of teams cause this)

    // Buffer not used if comptime board being used, hence else [0]u8
    // TODO: Honestly remove the whole baking into executable memory thing, and instead just get variables at compile time and make at runtime
    var buff: if (!comptimeInit) [totalSize]u8 else [0]u8 = undefined;
    var allocImpl = (comptime GameAllocator.getType(comptimeInit)).init(&buff);

    // var allocImpl = std.heap.DebugAllocator(.{}){};
    // defer _ = allocImpl.deinit();

    var gameBoard = try GameBoard.init(allocImpl.allocator(), comptime if (!comptimeInit) OPTIONS.width else config.width.?, comptime if (!comptimeInit) OPTIONS.height else config.height.?, comptime if (!comptimeInit) OPTIONS.numMines else config.num_mines.?, rngImpl.interface());
    var flagBitset = try FlagBitset.init(allocImpl.allocator(), boardSize, numTeams);

    defer gameBoard.deinit();

    try runGame(&gameBoard, &flagBitset, TerminalGameIo, init.io);
}

fn runGame(gameBoard: *GameBoard, flagBitset: *FlagBitset, GameIoImpl: anytype, io: std.Io) anyerror!void {
    comptime GameIo.validateGameIo(GameIoImpl);

    gameLoop: while (true) {
        try GameIoImpl.renderBoardDebug(gameBoard);
        const userAction = try GameIoImpl.getUserInput(io);
        if (userAction.flag) {
            const bitsetIndex = GameBoard.getCellIndex(@as(u32, @intCast(userAction.row)), @as(u32, @intCast(userAction.col)), gameBoard.width);
            flagBitset.toggleFlag(bitsetIndex, userAction.team) catch |err| switch (err) {
                error.InvalidTeamNumber => {
                    print("Invalid team number\n", .{});
                },
                error.InvalidCell => {
                    print("Invalid cell, idk how you clicked that parser wrong probably\n", .{});
                },
            };
        } else if (gameBoard.revealCell(flagBitset, userAction.team, userAction.row, userAction.col)) |result| {
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
