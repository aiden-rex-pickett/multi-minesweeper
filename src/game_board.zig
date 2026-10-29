//! This module represents a minesweeper board that contains an array of cells

const std = @import("std");
const print = std.debug.print;
const testing = std.testing;

const FlagBitset = @import("flag_bitset.zig");

const Self = @This();

pub const MAX_DIMENSION: u32 = 10_000;
pub const MAX_TEAMS: u10 = ~@as(u10, 0);

cells: []Cell, // Array of cells representing the board
width: u32, // Board width
height: u32, // Board height
cellsLeft: u32, // Number of unrevealed non-mine cells left
allocator: std.mem.Allocator, // Allocator that allocated the array of cells and that can be used for flood fill scratch memory

/// The packed struct that represents a minesweeper cell
pub const Cell = packed struct(u16) {
    mine: bool,
    revealed: bool,
    neighbors: u4,
    team: u10,
};

/// Initalizes a new Board of the provided width, height, and number of mines using the provided buffer.
/// The buffer must be at least 4 * width * height bytes.
/// If the buffer is not large enough, an UndersizedBuffer error is returned
/// If you try to initalize a board with more mines than cells, a TooManyMines error is returned
pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, numMines: u32, rand: std.Random) error{ OutOfMemory, TooManyMines, InvalidDimensions }!Self {
    const totalCells, const overflow = @mulWithOverflow(width, height);
    if (overflow == 1 or totalCells > MAX_DIMENSION * MAX_DIMENSION or totalCells == 0)
        return error.InvalidDimensions;

    if (numMines > width * height) {
        return error.TooManyMines;
    }

    var board = Self{
        .cells = try allocator.alloc(Cell, width * height),
        .width = width,
        .height = height,
        .cellsLeft = totalCells - numMines,
        .allocator = allocator,
    };

    board.fillBoard(numMines, rand);
    board.setNeighborsAll();
    return board;
}

pub fn deinit(self: *const Self) void {
    self.allocator.free(self.cells);
}

/// Gets an optional pionter to the cell at the provided row and column.
/// If the row and column are not valid the optional is empty, else the optional is populated
pub inline fn getCell(self: *const Self, row: i32, col: i32) ?*Cell {
    if (row < 0 or row >= self.height or col < 0 or col >= self.width) return null;
    return &self.cells[getCellIndex(@as(u32, @intCast(row)), @as(u32, @intCast(col)), self.width)];
}

/// Basically a macro for doing 2d indexing in 1d array.
pub inline fn getCellIndex(row: u32, col: u32, width: u32) u32 {
    return row * width + col;
}

/// Type returned by clickCell representing the result of the click
const RevealResult = enum {
    Exploded,
    Safe,
    Win,
    Invalid,
    Nop,
};

/// Reveals a cell, returning an enum representing what happened
pub fn revealCell(self: *Self, flagBitset: *const FlagBitset, team: u32, row: i32, col: i32) error{OutOfMemory}!RevealResult {
    const cell = self.getCell(row, col) orelse return .Invalid;

    const flagged = flagBitset.flagged(getCellIndex(@as(u32, @intCast(row)), @as(u32, @intCast(col)), self.width), team) catch return .Invalid;
    if (cell.revealed or flagged) return .Nop;

    cell.revealed = true;
    if (cell.mine) return .Exploded;

    self.cellsLeft -= 1;

    if (cell.neighbors == 0)
        try self.floodFill(flagBitset, team, @as(u32, @intCast(row)), @as(u32, @intCast(col)));

    if (self.cellsLeft == 0) return .Win;

    return .Safe;
}

/// Runs a flood fill from the provided row and column. It is assumed that the cell at row, column are valid, revealed, and have a neighbor count of 0
fn floodFill(self: *Self, flagBitset: *const FlagBitset, team: u32, row: u32, col: u32) error{OutOfMemory}!void {
    var stack = try self.allocator.alloc(u32, self.width * self.height);
    defer self.allocator.free(stack);
    stack[0] = getCellIndex(row, col, self.width);

    var stackTopNext: usize = 1;

    while (stackTopNext > 0) {
        const cellIndex = stack[stackTopNext - 1];
        stackTopNext -= 1;

        if (self.cells[cellIndex].neighbors == 0) self.addValidNeighbors(flagBitset, team, cellIndex, stack, &stackTopNext);
    }
}

/// Adds all valid neighbors of a cell to the given stack, marking as revealed on push
inline fn addValidNeighbors(self: *Self, flagBitset: *const FlagBitset, team: u32, cellIndex: u32, stack: []u32, stackTopNext: *usize) void {
    const width = self.width;

    const row = cellIndex / width;
    const col = cellIndex % width;

    const directions = [_]struct { dr: i32, dc: i32 }{
        .{ .dr = -1, .dc = -1 }, .{ .dr = -1, .dc = 0 }, .{ .dr = -1, .dc = 1 },
        .{ .dr = 0, .dc = -1 },  .{ .dr = 0, .dc = 1 },  .{ .dr = 1, .dc = -1 },
        .{ .dr = 1, .dc = 0 },   .{ .dr = 1, .dc = 1 },
    };
    for (directions) |direction| {
        const newRowSigned: i32 = @as(i32, @intCast(row)) + direction.dr;
        const newColSigned: i32 = @as(i32, @intCast(col)) + direction.dc;

        if (newRowSigned < 0 or newRowSigned >= self.height or newColSigned < 0 or newColSigned >= self.width) continue;

        const newIndex = getCellIndex(@as(u32, @intCast(newRowSigned)), @as(u32, @intCast(newColSigned)), self.width);
        const newCell = &self.cells[newIndex];

        const flagged = flagBitset.flaggedUnchecked(newIndex, team);
        if (!newCell.revealed and !flagged) {
            newCell.revealed = true;
            self.cellsLeft -= 1;
            stack[stackTopNext.*] = newIndex;
            stackTopNext.* += 1;
        }
    }
}

/// this function validates that the neighbor numbers for every mine are correct, based
/// on the number of mine cells surrounding it. For testing purposes and internal validation
///
/// Note that this is only valid in so far as the mine bit is being set correctly
pub fn validate_neighbor_counts(self: *const Self) bool {
    for (self.cells, 0..) |cell, i| {
        const row: i32 = @intCast(i / self.width);
        const col: i32 = @intCast(i % self.width);
        const seen = cell.neighbors;

        var actual: i32 = 0;

        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                if (dy == 0 and dx == 0) continue;
                actual += if (self.getCell(row + dy, col + dx)) |check_cell| @intFromBool(check_cell.mine) else 0;
            }
        }

        if (seen != actual) {
            print("ERROR: INVALID BOARD.\n Row: {}, Col: {}, actual: {}, seen: {}\n", .{ row, col, actual, seen });
            unreachable;
        }
    }

    return true;
}

/// Does a fisher-yates shuffle to place the mines
fn fillBoard(self: *Self, numMines: u32, rand: std.Random) void {
    @memset(self.cells[0..numMines], Cell{
        .mine = true,
        .revealed = false,
        .neighbors = 0,
        .team = 0,
    });
    @memset(self.cells[numMines..self.cells.len], @bitCast(@as(u16, 0)));

    for (0..numMines) |i| {
        const j = rand.intRangeAtMost(usize, i, self.cells.len - 1);
        std.mem.swap(Cell, &self.cells[i], &self.cells[j]);
    }
}

/// Sets the neighbors field for each of the Cells in the board, filling out the numbers properly
/// To be used after fillBoard is called on a fresh board
fn setNeighborsAll(self: *Self) void {
    for (self.cells, 0..) |cell, i| {
        if (!cell.mine) continue;
        const row = @as(i32, @intCast(i / self.width));
        const col = @as(i32, @intCast(i % self.width));

        const directions = [_]struct { dr: i32, dc: i32 }{
            .{ .dr = -1, .dc = -1 }, .{ .dr = -1, .dc = 0 }, .{ .dr = -1, .dc = 1 },
            .{ .dr = 0, .dc = -1 },  .{ .dr = 0, .dc = 1 },  .{ .dr = 1, .dc = -1 },
            .{ .dr = 1, .dc = 0 },   .{ .dr = 1, .dc = 1 },
        };
        for (directions) |direction| {
            if (self.getCell(row + direction.dr, col + direction.dc)) |neighborCell| neighborCell.neighbors += 1;
        }
    }
}

// -------------------- TESTS -------------------- //

const gpa = std.heap.DebugAllocator(.{});

test "too-many-mines" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (1..20) |width| {
        for (1..20) |height| {
            for ((width * height + 1)..1000) |numMines| {
                try testing.expectError(error.TooManyMines, Self.init(interface, @as(u32, @intCast(width)), @as(u32, @intCast(height)), @as(u32, @intCast(numMines)), prng.random()));
            }
        }
    }
}

test "mine-setup-validation" {
    const min_width = 5;
    const min_height = 5;
    const max_width = 100;
    const max_height = 100;

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    const rand = prng.random();

    const num_shapes = 100;
    for (0..num_shapes) |_| {
        const width = rand.intRangeAtMost(u32, min_width, max_width);
        const height = rand.intRangeAtMost(u32, min_height, max_height);
        const num_threads = 22;

        const mines_step = (width * height) / (num_threads + 2);

        const Thread = std.Thread;

        const board_test = struct {
            // Testing function
            fn testBoard(board_width: u32, board_height: u32, num_mines: u32, random: std.Random, result: *bool) !void {
                var alloc = gpa{};
                defer _ = alloc.deinit();
                var game_board = try Self.init(alloc.allocator(), board_width, board_height, num_mines, random);
                defer game_board.deinit();
                result.* = game_board.validate_neighbor_counts();
            }
        };

        var threads: [num_threads]Thread = undefined;
        var results: [num_threads]bool = undefined;

        {
            var i: u32 = 1;
            while (i < num_threads + 1) : (i += 1) {
                threads[i - 1] = try Thread.spawn(.{}, board_test.testBoard, .{ width, height, @as(u32, @intCast(i)) * mines_step, rand, &results[i - 1] });
            }

            for (threads) |thread| {
                thread.join();
            }
        }

        for (results) |result| {
            try testing.expect(result);
        }
    }
}

test "get-mines-out-of-bounds" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (1..100) |width| {
        for (1..100) |height| {
            var board = try Self.init(interface, @as(u32, @intCast(width)), @as(u32, @intCast(height)), 0, prng.random());
            defer board.deinit();
            var r: i32 = -100;
            while (r < 0) : (r += 1) {
                var c: i32 = -100;
                while (c < 0) : (c += 1) {
                    try testing.expect(board.getCell(r, c) == null);
                }
            }
            r = @intCast(width);
            while (r < 200) : (r += 1) {
                var c: i32 = @intCast(height);
                while (c < 200) : (c += 1) {
                    try testing.expect(board.getCell(r, c) == null);
                }
            }
        }
    }
}

test "invalid_dimension_low" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    try testing.expectError(error.InvalidDimensions, Self.init(interface, 0, 0, 0, prng.random()));
    try testing.expectError(error.InvalidDimensions, Self.init(interface, 10, 0, 0, prng.random()));
    try testing.expectError(error.InvalidDimensions, Self.init(interface, 0, 10, 0, prng.random()));
}

test "invalid_dimension_high" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);

    for (1..100) |width| {
        for (1..100) |height| {
            try testing.expectError(error.InvalidDimensions, Self.init(interface, MAX_DIMENSION + @as(u32, @intCast(width)), MAX_DIMENSION + @as(u32, @intCast(height)), 0, prng.random()));
        }
    }
}

test "get_cell_mutable_pointer" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);

    var game_board: Self = try .init(interface, 10, 10, 0, prng.random());
    defer game_board.deinit();

    const cell = game_board.getCell(0, 0) orelse unreachable;
    const before = game_board.cells[0];
    cell.team = 10;
    try testing.expect(10 == game_board.cells[0].team);
    try testing.expect(before.mine == game_board.cells[0].mine);
    try testing.expect(before.revealed == game_board.cells[0].revealed);
    try testing.expect(before.neighbors == game_board.cells[0].neighbors);
}

test "mine_click_looses" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);

    var game_board: Self = try .init(interface, 1, 1, 1, prng.random());
    defer game_board.deinit();

    try testing.expect(try game_board.revealCell(0, 0) == .Exploded);
    try testing.expect(game_board.cells[0].mine and game_board.cells[0].revealed);
}

test "flood_fill_fills" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);

    for (0..10) |row| {
        for (0..10) |col| {
            var game_board: Self = try .init(interface, 10, 10, 0, prng.random());
            defer game_board.deinit();
            try testing.expect(try game_board.revealCell(@as(i32, @intCast(row)), @as(i32, @intCast(col))) == .Win);
            for (game_board.cells) |cell| {
                try testing.expect(cell.revealed);
            }
        }
    }
}
