/// Represents the allocator for the application, being a FBA over static memory for comptime boards
/// and whatever other kind of allocator we want to use for the dynamic ones
const std = @import("std");

const config = @import("config");

const GameBoard = @import("game_board.zig");

pub fn getType(comptime fixed: bool) type {
    return struct {
        const Self = @This();

        impl: std.heap.FixedBufferAllocator,

        pub fn init(buff: []u8) Self {
            if (fixed) {
                const precomputed = comptime precompute: {
                    const globals = struct {
                        pub threadlocal var staticMem: [config.width.? * config.height.? * @sizeOf(GameBoard.Cell) + config.width.? * config.height.? * @sizeOf(GameBoard.Pair)]u8 = undefined;
                    };
                    break :precompute .{ .storage = globals };
                };
                return .{ .impl = std.heap.FixedBufferAllocator.init(&precomputed.storage.staticMem) };
            }
            return .{ .impl = std.heap.FixedBufferAllocator.init(buff) };
        }

        pub inline fn allocator(self: *Self) std.mem.Allocator {
            return self.impl.allocator();
        }
    };
}
