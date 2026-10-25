const std = @import("std");
const config = @import("config");
const print = std.debug.print;
const Io = std.Io;

const GameBoard = @import("game_board.zig");
const Renderer = @import("renderer.zig");
const TerminalRenderer = @import("terminal_renderer.zig");

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

        const boardWidth = 15;
        const boardHeight = 15;
        const numMines = 99;

        // WARNING: May need to change this to defer to the heap if stack size becomes an issue
        var buffer: [boardWidth * boardHeight * @sizeOf(GameBoard.Cell) * 2]u8 align(@alignOf(GameBoard.Cell)) = undefined;

        break :else_branch try GameBoard.init(&buffer, boardWidth, boardHeight, numMines, rng_impl.interface());
    };

    var renderer = TerminalRenderer{};
    const terminalRenderer: Renderer = renderer.renderer();

    while (true) gameLoop: {
        try terminalRenderer.renderBoardDebug(&gameBoard);
        const a = try terminalRenderer.getUserInput(init.io);
        if (a.flag) {
            gameBoard.toggleFlag(a.row, a.col);
        } else {
            switch (gameBoard.clickCell(a.row, a.col)) {
                .Exploded => |cell| {
                    print("OH NO. CELL AT {} WAS A MINE!\n", .{cell.mine});
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
        }
    }

    _ = gameBoard.validate_neighbor_counts();
}
