const std = @import("std");
const config = @import("config");
const print = std.debug.print;
const Io = std.Io;

const GameBoard = @import("game_board.zig");
const GameIo = @import("game_io_interface.zig");
const TerminalGameIo = @import("terminal_game_io.zig");

// TODO: Optimize buffer allocation to be as small as possible
pub fn main(init: std.process.Init) !void {
    const rng_impl: std.Random.IoSource = .{ .io = init.io };

    var GPA = std.heap.DebugAllocator(.{}){};
    defer _ = GPA.deinit();

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

        const boardWidth = 4;
        const boardHeight = 4;
        const numMines = 15;

        // WARNING: May need to change this to defer to the heap if stack size becomes an issue
        // TODO: Dejankify this
        // var buffer: [boardWidth * boardHeight * @sizeOf(GameBoard.Cell) + (boardWidth * boardHeight * @sizeOf(u64))]u8 align(@alignOf(GameBoard.Cell)) = undefined;
        // var fba = std.heap.FixedBufferAllocator.init(&buffer);
        //
        // break :else_branch try GameBoard.init(fba.allocator(), boardWidth, boardHeight, numMines, rng_impl.interface());

        break :else_branch try GameBoard.init(GPA.allocator(), boardWidth, boardHeight, numMines, rng_impl.interface());
    };
    defer gameBoard.deinit();

    comptime GameIo.validateGameIo(TerminalGameIo);

    gameLoop: while (true) {
        try TerminalGameIo.renderBoardDebug(&gameBoard);
        const userAction = try TerminalGameIo.getUserInput(init.io);
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
