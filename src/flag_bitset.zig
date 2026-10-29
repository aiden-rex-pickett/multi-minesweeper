//! This struct represents a bitset of flagged states for multiple teams

const std = @import("std");
const print = std.debug.print;
const testing = std.testing;

const GameBoard = @import("game_board.zig");

const Self = @This();

bitsets: []u64,
teamSetWidth: u64,
allocator: std.mem.Allocator,

/// Initalizes a new bitset, returning errors if the arguments are invalid or the allocator runs out of memory
pub fn init(allocator: std.mem.Allocator, boardSize: u32, teamCount: usize) error{ OutOfMemory, InvalidDimensions, InvalidTeamNumber }!Self {
    if (boardSize > GameBoard.MAX_DIMENSION * GameBoard.MAX_DIMENSION or boardSize == 0)
        return error.InvalidDimensions;

    if (teamCount > GameBoard.MAX_TEAMS or teamCount == 0)
        return error.InvalidTeamNumber;

    // Width of the bitset for each team, rounded up to nearest multiple of 64
    const teamSetWidth: u64 = boardSize / 64 + if (boardSize & 63 != 0) @as(u64, 1) else @as(u64, 0);
    const bitsets = try allocator.alloc(u64, teamSetWidth * teamCount);
    @memset(bitsets, 0);

    return Self{
        .bitsets = bitsets,
        .teamSetWidth = teamSetWidth,
        .allocator = allocator,
    };
}

/// Frees bitset memory with the allocator passed to the bitset in init()
pub fn deinit(self: *const Self) void {
    self.allocator.free(self.bitsets);
}

/// Tells if a cell is flagged for a team in the bitset
pub inline fn flagged(self: *const Self, index: usize, team: usize) error{ InvalidTeamNumber, InvalidCell }!bool {
    const bitsetIndex = try self.getBitsetIndex(index, team);
    return self.bitsets[bitsetIndex] & (@as(u64, 1) << @intCast(index & 63)) != 0;
}

/// Toggles the flagged state of a cell in the bitset
pub inline fn toggleFlag(self: *Self, index: usize, team: usize) error{ InvalidTeamNumber, InvalidCell }!void {
    const bitsetIndex = try self.getBitsetIndex(index, team);
    self.bitsets[bitsetIndex] ^= (@as(u64, 1) << @intCast(index & 63));
}

/// This function gets the bitset index into the array, also checking the arguments and returns an error if they are invalid
inline fn getBitsetIndex(self: *const Self, index: usize, team: usize) error{ InvalidTeamNumber, InvalidCell }!usize {
    if (team > self.bitsets.len / self.teamSetWidth or team == 0)
        return error.InvalidTeamNumber;

    const bitsetIndex = ((team - 1) * self.teamSetWidth) + index / 64;
    return if (bitsetIndex >= self.bitsets.len) error.InvalidCell else bitsetIndex;
}

/// Unchecked version of flagged, don't use until production or you are sure it will speed things up
pub inline fn flaggedUnchecked(self: *const Self, index: usize, team: usize) bool {
    return self.bitsets[((team - 1) * self.teamSetWidth) + index / 64] & (@as(u64, 1) << @intCast(index & 63)) != 0;
}

/// Unchecked version of toggleFlag, don't use until production or you are sure it will speed things up
pub inline fn toggleFlagUnchecked(self: *Self, index: usize, team: usize) void {
    self.bitsets[((team - 1) * self.teamSetWidth) + index / 64] ^= (@as(u64, 1) << @intCast(index & 63));
}

// -------------------- TESTS -------------------- //

const gpa = std.heap.DebugAllocator(.{});

test "set_flag_simple" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 100, 1);
    defer bitset.deinit();

    try bitset.toggleFlag(50, 1);
    try testing.expect(try bitset.flagged(50, 1));
    for (0..100) |i| {
        if (i == 50) continue;
        try testing.expect(!(try bitset.flagged(i, 1)));
    }
}

test "toggle_flag_toggles" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 100, 1);
    defer bitset.deinit();

    try bitset.toggleFlag(50, 1);
    try testing.expect(try bitset.flagged(50, 1));
    try bitset.toggleFlag(50, 1);
    try testing.expect(!try bitset.flagged(50, 1));
}

test "toggle_all_all_set" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 100, 1);
    defer bitset.deinit();

    for (0..100) |i| {
        try bitset.toggleFlag(i, 1);
    }

    for (0..100) |i| {
        try testing.expect(try bitset.flagged(i, 1));
    }

    for (0..100) |i| {
        try bitset.toggleFlag(i, 1);
    }

    for (0..100) |i| {
        try testing.expect(!try bitset.flagged(i, 1));
    }
}

test "toggle_all_alternating" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 100, 1);
    defer bitset.deinit();

    for (0..100) |i| {
        if (i % 2 == 0)
            try bitset.toggleFlag(i, 1);
    }

    for (0..100) |i| {
        if (i % 2 == 0) {
            try testing.expect(try bitset.flagged(i, 1));
        } else try testing.expect(!try bitset.flagged(i, 1));
    }

    for (0..100) |i| {
        try bitset.toggleFlag(i, 1);
    }

    for (0..100) |i| {
        if (i % 2 == 0) {
            try testing.expect(!try bitset.flagged(i, 1));
        } else try testing.expect(try bitset.flagged(i, 1));
    }
}

test "toggle_flag_simple_multiple_teams" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 100, 2);
    defer bitset.deinit();

    try bitset.toggleFlag(50, 1);
    try testing.expect(try bitset.flagged(50, 1));
    for (0..100) |i| {
        if (i == 50) continue;
        try testing.expect(!(try bitset.flagged(i, 1)));
    }
    for (0..100) |i| {
        try testing.expect(!try bitset.flagged(i, 2));
    }
    try bitset.toggleFlag(50, 2);
    for (0..100) |i| {
        if (i == 50) continue;
        try testing.expect(!(try bitset.flagged(i, 2)));
    }
    for (0..100) |i| {
        if (i == 50) continue;
        try testing.expect(!(try bitset.flagged(i, 1)));
    }
}

test "fresh_board_0s" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 100_000, 1023);
    defer bitset.deinit();
    for (1..1023) |team| {
        for (0..100_000) |i| {
            try testing.expect(!try bitset.flagged(i, team));
        }
    }
}

test "big_board_middle" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 1_000, 200);
    defer bitset.deinit();

    try bitset.toggleFlag(342, 1);

    for (0..1_000) |i| {
        if (i == 342) continue;
        try testing.expect(!try bitset.flagged(i, 1));
    }
}

test "all_flags_set_on_one_team_none_on_other" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 10_000, 1000);
    defer bitset.deinit();

    for (0..10_000) |i| {
        for (1..1001) |teamNum| {
            if (teamNum % 2 == 0) {
                try bitset.toggleFlag(i, teamNum);
            }
        }
    }
    for (0..10_000) |i| {
        for (1..1001) |teamNum| {
            if (teamNum % 2 == 1) {
                try testing.expect(!try bitset.flagged(i, teamNum));
            } else try testing.expect(try bitset.flagged(i, teamNum));
        }
    }
}

test "adjacent_team_flags_top_and_bottom" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 64, 2);
    defer bitset.deinit();

    for (0..64) |i| {
        try bitset.toggleFlag(i, 1);
    }

    for (0..64) |i| {
        try testing.expect(try bitset.flagged(i, 1));
    }
    for (0..64) |i| {
        try testing.expect(!try bitset.flagged(i, 2));
    }
}

test "discontiguous_team_flags_top_and_bottom" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 64, 3);
    defer bitset.deinit();

    for (0..64) |i| {
        try bitset.toggleFlag(i, 1);
    }

    for (0..64) |i| {
        try testing.expect(try bitset.flagged(i, 1));
    }
    for (0..64) |i| {
        try testing.expect(!try bitset.flagged(i, 3));
    }
    for (0..64) |i| {
        try testing.expect(!try bitset.flagged(i, 2));
    }
}

test "toggle_flag_many_many_teams" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 1_000, 200);
    defer bitset.deinit();

    for (1..201) |teamNum| {
        try bitset.toggleFlag(342, teamNum);
    }

    for (1..201) |teamNum| {
        for (0..1_000) |i| {
            if (i == 342) try testing.expect(try bitset.flagged(i, teamNum)) else {
                try testing.expect(!try bitset.flagged(i, teamNum));
            }
        }
    }
}

test "small_board_get_set" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 10, 1);
    defer bitset.deinit();

    try bitset.toggleFlag(5, 1);
    try testing.expect(try bitset.flagged(5, 1));
    for (0..10) |i| {
        if (i == 5) continue;
        try testing.expect(!(try bitset.flagged(i, 1)));
    }
}

test "big_board_get_set" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 100_000, 1);
    defer bitset.deinit();

    try bitset.toggleFlag(50_000, 1);
    try testing.expect(try bitset.flagged(50_000, 1));
    for (0..100_000) |i| {
        if (i == 50_000) continue;
        try testing.expect(!(try bitset.flagged(i, 1)));
    }
}

test "invalid_team_set_get" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    var bitset = try Self.init(interface, 2000, 10);
    defer bitset.deinit();
    for (0..2000) |i| {
        try testing.expectError(error.InvalidTeamNumber, bitset.flagged(i, 0));
        try testing.expectError(error.InvalidTeamNumber, bitset.flagged(i, 11));
        try testing.expectError(error.InvalidTeamNumber, bitset.flagged(i, 12));
        try testing.expectError(error.InvalidTeamNumber, bitset.flagged(i, 12));
        try testing.expectError(error.InvalidTeamNumber, bitset.toggleFlag(i, 0));
        try testing.expectError(error.InvalidTeamNumber, bitset.toggleFlag(i, 11));
        try testing.expectError(error.InvalidTeamNumber, bitset.toggleFlag(i, 12));
        try testing.expectError(error.InvalidTeamNumber, bitset.toggleFlag(i, 12));
    }
}

test "big_board_invalid" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    for (1..100) |i| {
        const boardSize = @as(u32, @intCast(GameBoard.MAX_DIMENSION * GameBoard.MAX_DIMENSION + i));
        try testing.expectError(error.InvalidDimensions, Self.init(interface, boardSize, 1));
    }
}

test "empty_board_invalid" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    try testing.expectError(error.InvalidDimensions, Self.init(interface, 0, 1));
}

test "too_many_teams_invalid" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    for (1..100) |i| {
        try testing.expectError(error.InvalidTeamNumber, Self.init(interface, 100, GameBoard.MAX_TEAMS + i));
    }
}

test "no_teams_invalid" {
    var alloc = gpa{};
    defer _ = alloc.deinit();
    const interface = alloc.allocator();

    try testing.expectError(error.InvalidTeamNumber, Self.init(interface, 100, 0));
}
