/// Terminal rendering and input interface for board game
/// TODO: Instead of using std.debug.print move to holding a file descriptor and printing/reading from
/// that instead, should make it easier to adapt to a networked version send to the network
const Self = @This();

const GameBoard = @import("game_board.zig");
const GameIo = @import("game_io_interface.zig");

const std = @import("std");
const print = std.debug.print;

pub fn renderBoard(board: *const GameBoard) anyerror!void {
    printBoard(board, comptime printCell);
}

pub fn renderBoardDebug(board: *const GameBoard) anyerror!void {
    printBoard(board, comptime printCellDebug);
}

/// Loops until user provides valid input to terminal
pub fn getUserInput(io: std.Io) anyerror!GameIo.Action {
    var inputBuffer: [1024]u8 = undefined;
    var stdin_read_wrap = std.Io.File.stdin().readerStreaming(io, &inputBuffer);
    const reader = &stdin_read_wrap.interface;

    const format = "(Format: <row>,<col><f|\"\">)\n";
    print("Enter action {s}", .{format});
    while (try reader.takeDelimiter('\n')) |line| {
        if (parseAction(line)) |action| return action else |_| {
            print("Invalid format. {s}", .{format});
        }
    } else {
        print("EOF reached, ending", .{});
        return error.noActionInput;
    }
}

/// Prints out board using whatever cell print function is given
fn printBoard(board: *const GameBoard, cellPrint: fn (cell: GameBoard.Cell) void) void {
    print("   ", .{});
    for (0..board.width) |i| {
        print(" {d:^3}", .{i});
    }
    print("\n", .{});
    print("   ", .{});
    for (0..board.width) |_| {
        print("----", .{});
    }
    print("\n", .{});
    for (0..board.height) |row| {
        print("{d:^3}", .{row});
        for (0..board.width) |col| {
            const cell = board.getCell(@intCast(row), @intCast(col)).?;
            cellPrint(cell.*);
        }
        print("|\n   ", .{});
        for (0..board.width) |_| {
            print("----", .{});
        }
        print("\n", .{});
    }
}

/// Prints a single cell
fn printCell(cell: GameBoard.Cell) void {
    if (!cell.revealed) {
        print("| █ ", .{});
    } else {
        print("| {} ", .{cell.neighbors});
    }
}

/// Prints a single cell for debug purposes
fn printCellDebug(cell: GameBoard.Cell) void {
    if (cell.mine) {
        print("| ● ", .{});
    } else {
        print("| {}", .{cell.neighbors});
        if (cell.revealed) print("r", .{}) else print(" ", .{});
    }
}

/// Parses an action input string, returning badFormat error if not parsable
fn parseAction(line: []const u8) !GameIo.Action {
    const rowStart: usize = first: for (0..line.len) |i| {
        const char = line[i];
        if (char == ' ') continue;
        if (!std.ascii.isDigit(char)) return error.badFormat;
        break :first i;
    } else return error.badFormat;

    if (!std.ascii.isDigit(line[rowStart])) return error.badFormat;

    const rowEnd = second: for (rowStart + 1..line.len) |i| {
        if (line[i] == ',') {
            break :second i - 1;
        }
    } else {
        return error.badFormat;
    };

    const colStart = rowEnd + 2;
    if (colStart >= line.len or !std.ascii.isDigit(line[colStart])) return error.badFormat;

    var colEnd = colStart;
    var flag = false;
    for (colStart + 1..line.len) |i| {
        if (line[i] == 'f') {
            colEnd = i - 1;
            flag = true;
            break;
        }
        if (!std.ascii.isDigit(line[i])) return error.badFormat;
    } else {
        colEnd = line.len - 1;
    }

    return GameIo.Action{
        .row = try std.fmt.parseInt(i32, line[rowStart .. rowEnd + 1], 10),
        .col = try std.fmt.parseInt(i32, line[colStart .. colEnd + 1], 10),
        .flag = flag,
        .team = 1, // Singleplayer
    };
}
