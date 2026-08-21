//! This module represents a minesweeper board
//! It contains an array of cells, as well as an allocator
//! for pointing to some scratch space to do bfs for flood fill

const std = @import("std");
const print = std.debug.print;

const Self = @This();

cells: []Cell,
width: u32,
height: u32,
scratchAllocator: std.heap.FixedBufferAllocator,

/// The packed struct that represents a minesweeper cell
const Cell = packed struct(u16) {
    mine: bool,
    flagged: bool,
    revealed: bool,
    neighbors: u4,
    team: u8,
    pad: u1 = 0,
};

/// Initalizes a new Board of the provided width, height, and number of mines using the provided buffer.
/// The buffer must be at least 4 * width * height bytes.
/// If the buffer is not large enough, an UndersizedBuffer error is returned
/// If you try to initalize a board with more mines than cells, a TooManyMines error is returned
pub fn init(buffer: []align(@alignOf(Cell)) u8, width: u32, height: u32, num_mines: u32, rand: std.Random) error{ UndersizedBuffer, TooManyMines }!Self {
    if (buffer.len < width * height * @sizeOf(Cell) * 2) {
        return error.UndersizedBuffer;
    }

    if (num_mines > width * height) {
        return error.TooManyMines;
    }

    const cellsSize = width * height * @sizeOf(Cell);

    var board = Self{
        .cells = std.mem.bytesAsSlice(Cell, buffer[0..cellsSize]),
        .width = width,
        .height = height,
        .scratchAllocator = .init(buffer[cellsSize..]),
    };

    board.fillBoard(num_mines, rand);
    board.setNeighbors();
    return board;
}

/// Gets an optional pionter to the cell at the provided row and column.
/// If the row and column are not valid the optional is empty, else the optional is populated
pub fn getCell(self: Self, row: i32, col: i32) ?*Cell {
    if (row < 0 or row >= self.height or col < 0 or col >= self.width) return null;
    return &self.cells[@as(u32, @intCast(row)) * self.width + @as(u32, @intCast(col))];
}

/// This function validates that the neighbor numbers for every mine are correct, based
/// on the number of mine cells surrounding it
///
/// Note that this is only valid in so far as the mine bit is being set correctly
pub fn validate_neighbor_counts(self: Self) bool {
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
            self.printBoard();
        }
    }

    return true;
}

/// Prints out the state of the board
pub fn printBoard(self: Self) void {
    for (0..self.width) |_| {
        print("----", .{});
    }
    print("\n", .{});
    for (0..self.height) |row| {
        for (0..self.width) |col| {
            printCell(self.cells[row * self.width + col]);
        }
        print("|\n", .{});
        for (0..self.width) |_| {
            print("----", .{});
        }
        print("\n", .{});
    }
}

/// Prints a single cell
fn printCell(cell: Cell) void {
    if (cell.mine) {
        print("|M{} ", .{cell.neighbors});
    } else if (cell.flagged) {
        print("| ⚑ ", .{});
    } else if (cell.revealed) {
        print("| █ ", .{});
    } else if (!cell.revealed) {
        print("| {} ", .{cell.neighbors});
    }
}

/// Does a fisher-yates shuffle to place the mines
fn fillBoard(self: *Self, numMines: u32, rand: std.Random) void {
    @memset(self.cells[0..numMines], Cell{
        .mine = true,
        .flagged = false,
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
fn setNeighbors(self: *Self) void {
    for (self.cells, 0..) |cell, i| {
        if (!cell.mine) continue;
        const row = i / self.width;
        const col = i % self.width;

        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            const r = @as(i32, @intCast(row)) + dy;
            if (r < 0 or r >= self.height) continue;

            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                if (dy == 0 and dx == 0) continue;
                const c = @as(i32, @intCast(col)) + dx;
                if (c < 0 or c >= self.width) continue;

                const index = @as(usize, @intCast(r)) * @as(usize, @intCast(self.width)) + @as(usize, @intCast(c));
                self.cells[index].neighbors += 1;
            }
        }
    }
}

// -------------------- TESTS -------------------- //

const gpa = std.heap.DebugAllocator(.{});

const testing = std.testing;

test "buffer-too-small-error" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 50);
    { // Basic test
        defer interface.free(buff);

        try testing.expectError(error.UndersizedBuffer, Self.init(buff, 10, 10, 20, prng.random()));
    }

    { // Size of board, but not enough scratch space
        buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 10 * 10 * 2);
        defer interface.free(buff);

        try testing.expectError(error.UndersizedBuffer, Self.init(buff, 10, 10, 20, prng.random()));
    }

    { // Same size, but slightly larger board
        buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 10 * 10 * 4);
        defer interface.free(buff);

        try testing.expectError(error.UndersizedBuffer, Self.init(buff, 10, 11, 20, prng.random()));
    }

    { // Doesn't change with number of mines
        buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 10 * 10 * 4);
        defer interface.free(buff);

        for (0..110) |numMines| {
            try testing.expectError(error.UndersizedBuffer, Self.init(buff, 10, 11, @as(u32, @intCast(numMines)), prng.random()));
        }
    }
}

test "too-many-mines" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    const buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 20 * 20 * 2 * 2);
    defer interface.free(buff);

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..20) |width| {
        for (0..20) |height| {
            for ((width * height + 1)..1000) |numMines| {
                try testing.expectError(error.TooManyMines, Self.init(buff, @as(u32, @intCast(width)), @as(u32, @intCast(height)), @as(u32, @intCast(numMines)), prng.random()));
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

    // 1000 different board shapes
    const num_shapes = 1000;
    for (0..num_shapes) |_| {
        const width = rand.intRangeAtMost(u32, min_width, max_width);
        const height = rand.intRangeAtMost(u32, min_height, max_height);
        const num_threads = 22;

        const mines_step = (width * height) / (num_threads + 2);

        const Thread = std.Thread;

        const board_test = struct {
            // Testing function
            fn testBoard(board_width: u32, board_height: u32, num_mines: u32, buffer: []align(@alignOf(Cell)) u8, random: std.Random, result: *bool) !void {
                print("THREAD_NUM: {}\n", .{Thread.getCurrentId()});
                print("board_width: {}, board_height: {}, mines: {}\n\n", .{ board_width, board_height, num_mines });

                var game_board = try Self.init(buffer, board_width, board_height, num_mines, random);
                result.* = game_board.validate_neighbor_counts();
            }
        };

        var threads: [num_threads]Thread = undefined;
        var results: [num_threads]bool = undefined;

        {
            var alloc = gpa{};
            defer _ = alloc.deinit();
            const interface = alloc.allocator();

            var real_alloc: std.heap.ArenaAllocator = .init(interface);
            defer real_alloc.deinit();
            var real_interface = real_alloc.allocator();

            var i: u32 = 1;
            while (i < num_threads + 1) : (i += 1) {
                const buff = try real_interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), width * height * 2 * 2);
                threads[i - 1] = try Thread.spawn(.{}, board_test.testBoard, .{ width, height, @as(u32, @intCast(i)) * mines_step, buff, rand, &results[i - 1] });
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

// Note: Expects set-mine to work
test "get-mines-test" {
    var alloc = gpa{};
    defer alloc.deinit();
    const interface = alloc.allocator();

    const buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 20 * 20 * 2 * 2);
    defer interface.free(buff);

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);

    // TODO: Finish, after set mine is built out
    var game_board: Self = .init(buff, 10, 10, 0, prng.random());
}
