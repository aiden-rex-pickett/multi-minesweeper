/// This file holds struct definitions for polymorphic IO purposes, containing the required methods
const std = @import("std");

const FlagBitset = @import("flag_bitset.zig");
const GameBoard = @import("game_board.zig");

/// info struct about a player action taken
pub const Action = struct {
    row: i32,
    col: i32,
    flag: bool,
    team: u32,
};

/// The required methods to be a gameIo interface
const reqMethods = .{
    // TODO: Change these to not be anyerror but some more useful error union once we know common errors
    // AIs idea: pub const UniversalIoError = error{
    //     /// The communication channel closed, the GUI window was shut,
    //     /// or the carrier pigeon never returned.
    //     Disconnected,
    //
    //     /// Waited too long for input or an acknowledgment from the peer/user.
    //     Timeout,
    //
    //     /// The incoming payload (a malformed network packet, a corrupted GUI event,
    //     /// or garbled smoke signals) couldn't be parsed or understood.
    //     InvalidData,
    //
    //     /// The output buffer is full, or the message is too large to transmit
    //     /// through the current medium.
    //     CapacityExceeded,
    //
    //     /// A catch-all for an unexpected low-level failure of the underlying
    //     /// medium (e.g., a broken pipe, a GPU crash, or a sudden gust of wind).
    //     IoFailure,
    // };

    .{ .name = "renderBoard", .signature = fn (board: *const GameBoard, flagBitset: *const FlagBitset) anyerror!void },
    .{ .name = "renderBoardDebug", .signature = fn (board: *const GameBoard, flagBitset: *const FlagBitset) anyerror!void },
    .{ .name = "getUserInput", .signature = fn (io: std.Io) anyerror!Action },
};

/// Validates that a given type T has the required methods to be a gameIo interface
pub fn validateGameIo(T: type) void {
    if (!@inComptime()) @compileError("The validateGameIo can only be used at Comptime to validate comptime polymorphism of a given type.");

    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError(std.fmt.comptimePrint("Provided gameIo type {s} is not a struct. All gameIo interfaces must be structs", .{@typeName(T)}));
    }

    inline for (reqMethods) |method| {
        if (!@hasDecl(T, method.name)) {
            @compileError(std.fmt.comptimePrint("The type {s} does not implement the required method {s} to be a gameIo interface", .{ @typeName(T), method.name }));
        }
        const methodType = @TypeOf(@field(T, method.name));
        if (methodType != method.signature) {
            @compileError(std.fmt.comptimePrint(
                \\ The {s} method on type {s} does not have the correct function signature.
                \\ The signature for {s} should be {s}, but is {s}
            , .{ method.name, @typeName(T), method.name, @typeName(method.signature), @typeName(methodType) }));
        }
    }
}
