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
pub fn init(buffer: []align(@alignOf(Cell)) u8, width: u32, height: u32, numMines: u32) error{ UndersizedBuffer, TooManyMines }!Self {
    if (buffer.len < width * height * @sizeOf(Cell) * 2) {
        return error.UndersizedBuffer;
    }

    if (numMines > width * height) {
        return error.TooManyMines;
    }

    const cellsSize = width * height * @sizeOf(Cell);

    var board = Self{
        .cells = std.mem.bytesAsSlice(Cell, buffer[0..cellsSize]),
        .width = width,
        .height = height,
        .scratchAllocator = .init(buffer[cellsSize..]),
    };

    board.fillBoard(numMines);
    board.setNeighbors();
    return board;
}

/// Does a fisher-yates shuffle to place the mines
fn fillBoard(self: *Self, numMines: u32) void {
    @memset(self.cells[0..numMines], Cell{
        .mine = true,
        .flagged = false,
        .revealed = false,
        .neighbors = 0,
        .team = 0,
    });
    @memset(self.cells[numMines..self.cells.len], @bitCast(@as(u16, 0)));

    var prng: std.Random.DefaultPrng = .init(42);
    const rand = prng.random();

    for (0..numMines) |i| {
        const j = rand.intRangeAtMost(usize, i, self.cells.len - 1);
        std.mem.swap(Cell, &self.cells[i], &self.cells[j]);
    }
}

/// Sets the neighbors field for each of the Cells in the board, filling out the numbers properly
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
                const c = @as(i32, @intCast(col)) + dx;
                if (c < 0 or c >= self.width) continue;

                const index = @as(usize, @intCast(r)) * @as(usize, @intCast(self.width)) + @as(usize, @intCast(c));
                self.cells[index].neighbors += 1;
            }
        }
    }
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

fn printCell(cell: Cell) void {
    if (cell.mine) {
        print("| ⬤ ", .{});
    } else if (cell.flagged) {
        print("| ⚑ ", .{});
    } else if (cell.revealed) {
        print("| █ ", .{});
    } else if (!cell.revealed) {
        print("| {} ", .{cell.neighbors});
    }
}

// TODO: Tests that check invariants of the board state

const gpa = std.heap.DebugAllocator(.{});

const testing = std.testing;

test "buffer-too-small-error" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 50);
    { // Basic test
        defer interface.free(buff);

        try testing.expectError(error.UndersizedBuffer, Self.init(buff, 10, 10, 20));
    }

    { // Size of board, but not enough scratch space
        buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 10 * 10 * 2);
        defer interface.free(buff);

        try testing.expectError(error.UndersizedBuffer, Self.init(buff, 10, 10, 20));
    }

    { // Same size, but slightly larger board
        buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 10 * 10 * 4);
        defer interface.free(buff);

        try testing.expectError(error.UndersizedBuffer, Self.init(buff, 10, 11, 20));
    }

    { // Doesn't change with number of mines
        buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 10 * 10 * 4);
        defer interface.free(buff);

        for (0..110) |numMines| {
            try testing.expectError(error.UndersizedBuffer, Self.init(buff, 10, 11, @as(u32, @intCast(numMines))));
        }
    }
}

test "too-many-mines" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    // TODO: Fix
    const buff = try interface.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(2), 10 * 10 * 4);
    defer interface.free(buff);
    for (0..20) |width| {
        for (0..20) |height| {
            for (0..width * height + 1) |numMines| {
                defer interface.free(buff);
                _ = try Self.init(buff, @as(u32, @intCast(width)), @as(u32, @intCast(height)), @as(u32, @intCast(numMines)));
            }
            for (width * height..1000) |numMines| {
                defer interface.free(buff);
                try testing.expectError(error.TooManyMines, Self.init(buff, 10, 10, @as(u32, @intCast(numMines))));
            }
        }
    }
}
