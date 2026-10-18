//! This module represents a minesweeper board, but is SOA and uses hella SIMD

// TODO:
//   1. SIMD Mine counting, using 8 shifted registers and then accumulate to that row
//   2. SIMD Flood fill, which will require massive architecture overhaul to store SOA with 0_count bitmask, mines bitmask,
//      and revealed bitmask. Then a u8 array to store computed mine adjacency numbers. But if I can, it would be sick as
//      the flood fill would take no memory. Can still use comptime baked-in memory too if I want. Maybe build as other file
//   3. SIMD collapse for checking victory? add collapse on ~revealed&~mines gives number of hidden and safe mines left
//   4. Dynamically flip board axes under the hood if board really skinny, so that simd lanes still get maximum value along rows, set bool member and check in getCellLocation and flip if so
//   5. Comment up

const std = @import("std");
const print = std.debug.print;

const mine_options = @import("config");

const Self = @This();

height: usize,
width: usize,
rowStride: usize,

// SOA fields to track board state (and do SIMD tehe)
revealed: []u64,
mineBitmask: []const u64,
zeroNeighborBitmask: []const u64,

// Computed for view once at initalization (also with SIMD tehe)
neighborCounts: []const u8,

pub const CellLocation = struct {
    arrayIndex: usize,
    bitOffset: u6,
};

pub const Coordinate = struct {
    x: usize,
    y: usize,
};

pub fn init(allocator: std.mem.Allocator, random: std.Random, width: usize, height: usize, numMines: usize) error{ TooManyMines, OutOfMemory }!Self {
    const rowStride = (width + 63) / 64;
    const toAlloc = rowStride * height;

    const revealed = try allocator.alloc(u64, toAlloc);
    @memset(revealed, 0);

    const mineBitmask = try allocator.alloc(u64, toAlloc);
    const zeroNeighborBitmask = try allocator.alloc(u64, toAlloc);
    const neighborCounts = try allocator.alloc(u8, width * height);

    var board: Self = Self{
        .height = height,
        .width = width,
        .rowStride = rowStride,
        .revealed = revealed,
        .mineBitmask = mineBitmask,
        .zeroNeighborBitmask = zeroNeighborBitmask,
        .neighborCounts = neighborCounts,
    };

    try board.placeMines(allocator, numMines, random);
    board.setNeighborCounts();

    return board;
}

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.revealed);
    allocator.free(@constCast(self.mineBitmask));
    allocator.free(@constCast(self.zeroNeighborBitmask));
    allocator.free(@constCast(self.neighborCounts));
}

// TODO: See if this is working manually
fn placeMines(self: *Self, allocator: std.mem.Allocator, mineCount: usize, random: std.Random) error{ TooManyMines, OutOfMemory }!void {
    const totalCells = self.width * self.height;
    if (mineCount > totalCells) return error.TooManyMines;

    var positions = try allocator.alloc(Coordinate, totalCells);
    defer allocator.free(positions);

    for (positions, 0..) |*pos, i| {
        const y = i / self.width;
        const x = i % self.width;
        pos.* = Coordinate{ .x = x, .y = y };
    }

    const mutableMines = @constCast(self.mineBitmask);
    @memset(mutableMines, 0);

    for (0..mineCount) |i| {
        const swapIdx = random.intRangeLessThan(usize, i, totalCells);
        const randomPos = positions[swapIdx];

        positions[swapIdx] = positions[i];
        positions[i] = randomPos;

        const loc = self.locateCell(randomPos.x, randomPos.y);
        const mask = @as(u64, 1) << loc.bitOffset;
        mutableMines[loc.arrayIndex] |= mask;
    }
}

// TODO: SIMD neighbor counting, as well as zero neighbor map while we have the vectors made. Use Fused SIMD Bitmask Generation with == I guess?
fn setNeighborCounts(self: *Self) void {
    _ = self;
    // GENERAL OUTLINE:
    // Collect into @Vector(64, u64) types currentRow >> 1/<< 1, topRow >> 1/>> 0/<< 1, bottomRow >> 1/>> 0/<< 1
    // This gives us all the effects from every direction to every cell in the current row, like bottomRow >> 1 gives us bitmask for all counts of cells down and to the right one, etc
    // Aggregate this into a @Vector(64, u8) (So that we can use it to add)
    // Use result of each lane to set self.neighborCounts appropriately
}

pub inline fn getCellLocation(self: Self, x: usize, y: usize) error{InvalidLocation}!CellLocation {
    const row_start = y * self.rowStride;
    const chunk_offset = x / 64;
    return CellLocation{
        .arrayIndex = row_start + chunk_offset,
        .bitOffset = @as(u6, @intCast(x % 64)),
    };
}
