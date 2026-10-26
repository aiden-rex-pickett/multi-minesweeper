/// Represents the allocator for the application, being a FBA over static memory for comptime boards
/// and whatever other kind of allocator we want to use for the dynamic ones
const std = @import("std");

const config = @import("config");

const GameBoard = @import("game_board.zig");

const buffer_size = if (config.width != null) config.width.? else 0 * if (config.height != null) config.height.? else 0 * @sizeOf(GameBoard.Cell) + if (config.width != null) config.width.? else 0 * if (config.height != null) config.height.? else 0 * @sizeOf(GameBoard.Pair);
export var staticMem: [buffer_size]u8 = undefined;

pub fn getType(comptime fixed: bool) type {
    return struct {
        const Self = @This();

        impl: std.heap.FixedBufferAllocator,

        pub fn init(buff: []u8) Self {
            if (fixed) {
                return .{ .impl = std.heap.FixedBufferAllocator.init(&staticMem) };
            }
            return .{ .impl = std.heap.FixedBufferAllocator.init(buff) };
        }

        pub inline fn allocator(self: *Self) std.mem.Allocator {
            return self.impl.allocator();
        }
    };
}
