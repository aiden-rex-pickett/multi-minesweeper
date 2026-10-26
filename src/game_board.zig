//! This module represents a minesweeper board
//! It contains an array of cells, as well as an allocator
//! for pointing to some scratch space to do bfs for flood fill

// TODO:
//   1. SIMD Mine counting, using 8 shifted registers and then accumulate to that row
//   2. SIMD Flood fill, which will require massive architecture overhaul to store SOA with 0_count bitmask, mines bitmask,
//      and revealed bitmask. Then a u8 array to store computed mine adjacency numbers. But if I can, it would be sick as
//      the flood fill would take no memory. Can still use comptime baked-in memory too if I want. Maybe build as other file

const std = @import("std");
const mine_options = @import("config");
const print = std.debug.print;

const Self = @This();

cells: []Cell,
width: u32,
height: u32,
cellsLeft: u32,
scratchAllocator: std.heap.FixedBufferAllocator,

/// The packed struct that represents a minesweeper cell
pub const Cell = packed struct(u16) {
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
        .cellsLeft = width * height - num_mines,
        .scratchAllocator = .init(buffer[cellsSize..]),
    };

    board.fillBoard(num_mines, rand);
    board.setNeighbors();
    return board;
}

/// Initalizes the board described by compile arguments that is baked into the executable.
/// This simply amounts to shuffling the mines with an entropy source at runtime, all other initalization
/// steps are handled at comptime if this option is used
pub fn comptime_init(rand: std.Random) Self {
    const precomputed = comptime precompute: {
        if (mine_options.width == null or mine_options.height == null or mine_options.num_mines == null)
            @compileError("Comptime board initalization (-Dfixed=true) attempted without providing all of the following arguments: -Dwidth, -Dheight, and -Dnum_mines arguments");

        const BoardConfig = struct {
            width: u32,
            height: u32,
            num_mines: u32,
        };

        const selected: BoardConfig = .{ .width = mine_options.width.?, .height = mine_options.height.?, .num_mines = mine_options.num_mines.? };

        if (selected.num_mines > selected.width * selected.height)
            @compileError("Comptime board initalization arguments invalid, more mines than there are cells. Make sure -Dnum_mines <= -Dwidth * -Dheight");

        const globals = struct {
            pub threadlocal var buff: [selected.width * selected.height]Cell = undefined;
            pub threadlocal var scratch_buff: [selected.width * selected.height * @sizeOf(Cell)]u8 = undefined;
        };

        break :precompute .{
            .width = selected.width,
            .height = selected.height,
            .num_mines = selected.num_mines,
            .storage = globals,
        };
    };

    var board = Self{
        .cells = &precomputed.storage.buff,
        .width = precomputed.width,
        .height = precomputed.height,
        .cellsLeft = precomputed.height * precomputed.width - precomputed.num_mines,
        .scratchAllocator = .init(&precomputed.storage.scratch_buff),
    };

    board.fillBoard(precomputed.num_mines, rand);
    board.setNeighbors();

    return board;
}

/// Gets an optional pionter to the cell at the provided row and column.
/// If the row and column are not valid the optional is empty, else the optional is populated
pub inline fn getCell(self: Self, row: i32, col: i32) ?*Cell {
    if (row < 0 or row >= self.height or col < 0 or col >= self.width) return null;
    return &self.cells[@as(u32, @intCast(row)) * self.width + @as(u32, @intCast(col))];
}

/// Type returned by toggleFlag representing the result of the flag
const FlagResult = enum {
    Invalid,
    Nop,
    Safe,
};

/// Flags a cell, returning an enum representing what happened
pub inline fn flagCell(self: *Self, row: i32, col: i32) FlagResult {
    if (self.getCell(row, col)) |cell| {
        if (!cell.revealed) {
            cell.flagged = !cell.flagged;
            return .Safe;
        }
        return .Nop;
    }

    return .Invalid;
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
pub fn revealCell(self: *Self, row: i32, col: i32) RevealResult {
    const cell = self.getCell(row, col) orelse return .Invalid;

    if (cell.flagged or cell.revealed) return .Nop;

    cell.revealed = true;
    if (cell.mine) return .Exploded;

    self.cellsLeft -= 1;
    if (self.cellsLeft == 0) return .Win;

    // TODO: BFS flood fill here with scratch space;

    return .Safe;
}

/// This function validates that the neighbor numbers for every mine are correct, based
/// on the number of mine cells surrounding it. For testing purposes and internal validation
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
            unreachable;
        }
    }

    return true;
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

    const num_shapes = 100;
    for (0..num_shapes) |_| {
        const width = rand.intRangeAtMost(u32, min_width, max_width);
        const height = rand.intRangeAtMost(u32, min_height, max_height);
        const num_threads = 22;

        const mines_step = (width * height) / (num_threads + 2);

        const Thread = std.Thread;

        const board_test = struct {
            // Testing function
            fn testBoard(board_width: u32, board_height: u32, num_mines: u32, buffer: []align(@alignOf(Cell)) u8, random: std.Random, result: *bool) !void {
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

test "flag-set-basic" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    const buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 30 * 30 * 2 * 2);
    defer interface.free(buff);

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var board = try Self.init(buff, 30, 30, 99, prng.random());
    for (0..30) |row| {
        for (0..30) |col| {
            const r = @as(i32, @intCast(row));
            const c = @as(i32, @intCast(col));
            const before = board.getCell(r, c).?.*;
            board.toggleFlag(r, c);
            const after = board.getCell(r, c).?.*;
            const fields = std.meta.fields(Cell);

            inline for (fields) |field| {
                const beforeVal = @field(before, field.name);
                const afterVal = @field(after, field.name);
                if (comptime std.mem.eql(u8, field.name, "flagged")) {
                    try testing.expect(beforeVal == !afterVal);
                } else {
                    try testing.expect(beforeVal == afterVal);
                }
            }
            try testing.expect(board.validate_neighbor_counts());
        }
    }
}

test "flag-set-aftereffect" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    const buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 30 * 30 * 2 * 2);
    defer interface.free(buff);

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var board = try Self.init(buff, 30, 30, 99, prng.random());

    const Pair = struct {
        row: usize,
        col: usize,
    };
    var flagSet = std.AutoHashMap(Pair, void).init(interface);
    defer flagSet.deinit();
    for (0..30) |row| {
        for (0..30) |col| {
            if (prng.random().intRangeAtMost(i32, 0, 10) < 7) {
                const r = @as(i32, @intCast(row));
                const c = @as(i32, @intCast(col));
                try flagSet.put(.{ .row = row, .col = col }, {});
                board.toggleFlag(r, c);
            }
        }
    }

    for (0..30) |row| {
        for (0..30) |col| {
            const cell = board.getCell(@intCast(row), @intCast(col)).?;
            if (flagSet.contains(Pair{ .row = row, .col = col })) {
                try testing.expect(cell.flagged);
            } else {
                try testing.expect(!cell.flagged);
            }
        }
    }
}

// TODO: Test for all the out of bounds being null for get mine
test "get-mines-out-of-bounds" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..100) |width| {
        for (0..100) |height| {
            const buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), width * height * 2 * 2);
            defer interface.free(buff);
            var board = try Self.init(buff, @as(u32, @intCast(width)), @as(u32, @intCast(height)), 0, prng.random());
            var r: i32 = -300;
            while (r < 0) : (r += 1) {
                var c: i32 = -300;
                while (c < 0) : (c += 1) {
                    try testing.expect(board.getCell(r, c) == null);
                }
            }
            r = @intCast(width);
            while (r < 300) : (r += 1) {
                var c: i32 = @intCast(height);
                while (c < 300) : (c += 1) {
                    try testing.expect(board.getCell(r, c) == null);
                }
            }
        }
    }
}

// TODO: Add basic test for get mine functionality, and after you change it it's right, also returns correct pointer and changes in cell array
test "get-mines-test" {
    // var alloc = gpa{};
    // defer alloc.deinit();
    // const interface = alloc.allocator();
    //
    // const buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 20 * 20 * 2 * 2);
    // defer interface.free(buff);
    //
    // var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    //
    // // TODO: Finish, after set mine is built out
    // var game_board: Self = .init(buff, 10, 10, 0, prng.random());
}
