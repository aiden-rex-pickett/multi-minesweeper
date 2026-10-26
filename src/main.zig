const std = @import("std");
const config = @import("config");
const print = std.debug.print;
const Io = std.Io;

const GameBoard = @import("game_board.zig");
const GameIo = @import("game_io_interface.zig");
const TerminalGameIo = @import("terminal_game_io.zig");

pub fn main(init: std.process.Init) !void {
    const rng_impl: std.Random.IoSource = .{ .io = init.io };

    var gameBoard: GameBoard = if (config.fixed)
        GameBoard.comptime_init(rng_impl.interface())
    else else_branch: {
        comptime { // Compile-time error if compile-time board generation options provided without providing -Dfixed
            const conf_opt = .{ .{
                .name = "Compile-time option -Dheight set without -Dfixed=true set",
                .val = config.height,
            }, .{ .name = "Compile-time option -Dwidth set without -Dfixed=true set", .val = config.width }, .{ .name = "Compile-time option -Dnum_mines  set without -Dfixed=true set", .val = config.num_mines } };
            for (conf_opt) |conf| {
                if (conf.val) |_| @compileError(conf.name);
            }
        }

        const boardWidth = 2;
        const boardHeight = 2;
        const numMines = 1;

        // WARNING: May need to change this to defer to the heap if stack size becomes an issue
        var buffer: [boardWidth * boardHeight * @sizeOf(GameBoard.Cell) * 2]u8 align(@alignOf(GameBoard.Cell)) = undefined;

        break :else_branch try GameBoard.init(&buffer, boardWidth, boardHeight, numMines, rng_impl.interface());
    };

    comptime GameIo.validateGameIo(TerminalGameIo);

    gameLoop: while (true) {
        try TerminalGameIo.renderBoardDebug(&gameBoard);
        const userAction = try TerminalGameIo.getUserInput(init.io);
        if (userAction.flag) switch (gameBoard.flagCell(userAction.row, userAction.col)) {
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

    _ = gameBoard.validate_neighbor_counts();
}
