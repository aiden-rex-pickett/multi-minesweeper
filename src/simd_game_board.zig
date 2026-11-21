//! Game board, but with a struct of bitsets instead of array of structs for cell representation.
//! Should make it really freaking fast

// TODO: Implment (Thanks for the notes clanka)
//
// # Architecture Note: SoA Bitset Grid + FBA Flood Fill
//
// ## 1. Memory Layout (Page Allocator + FBA)
// - Reserve one contiguous block from `std.heap.page_allocator` up front and wrap it in `std.heap.FixedBufferAllocator`.
// - Use `fba.reset()` between games of the same size instead of re-requesting OS pages.
// - For transient operations (like `floodFill` or mine generation), `alloc` at the start of the scope and `defer allocator.free(...)` before returning so the FBA tail pointer rewinds cleanly. Keep the inner loop strictly allocation-free.
//
// ## 2. Padded Row Stride (`u64` Word Alignment)
// - Pad the board with a **1-cell sentinel border** on all 4 sides (top, bottom, left, right) so flood fill never needs bounds checks.
// - Round each row's bit width up to a multiple of `64` (`u64` word boundary) so rows never share a 64-bit word:
//   - `words_per_row = std.math.divCeil(usize, width + 2, 64)`
//   - `stride_bits = words_per_row * 64`
//   - `total_words = (height + 2) * words_per_row`
// - Playable coordinate `(r, c)` maps to padded bit coordinate `(r + 1, c + 1)`.
// - Initialize the top sentinel row (`0`), bottom sentinel row (`height + 1`), left column (`bit 0`), and right column (`bit width + 1`) as `revealed = 1` and `is_zero = 0` during board setup.
//
// ## 3. Structure of Arrays (SoA) Bitsets
// Split cell state into separate `[]u64` bitsets sharing the exact same `total_words` layout:
// - `revealed`: `[]u64` (1 bit/cell — sentinel border initialized to `1`)
// - `mines`: `[]u64` (1 bit/cell)
// - `is_zero`: `[]u64` (1 bit/cell — precomputed `neighbors == 0` so flood fill never touches neighbor counts)
// - `flagged`: `[]u64` (per-team bitset, aligned to the same `words_per_row` stride)
// - `neighbors`: `[]u8` or 4-bit packed array (only read for UI/rendering or chording, not flood fill)
//
// ## 4. Flood Fill Implementation
// - **Algorithm:** Use a FIFO Breadth-First Search (BFS) ring buffer (`head` and `tail` indices with conditional wrap `if (idx == queue.len) idx = 0`, avoiding `%`), NOT iterative DFS.
// - **Queue Sizing:** Worst-case active BFS wave on an 8-connected grid is mathematically bounded by `(width * height + 1) / 2` `u32` entries (2 bytes per playable cell).
// - **Word-Level Optimization (Optional Next Step):** Because `revealed`, `is_zero`, and `flagged` share aligned `u64` words per row, propagate horizontal runs 64 bits at a time using `(word << 1) | (word >> 1)` and `@ctz` instead of stepping 1 cell at a time.
//
// ## 5. Build & Perf Reminders
// - Always benchmark large boards (e.g., `10,000 x 10,000`) with `-Doptimize=ReleaseFast` (default `Debug` safety checks add ~20x–30x overhead on tight loops).
// - Note that first-touch on freshly `mmap`'d pages triggers kernel zero-fill page faults; reusing the buffer via `fba.reset()` eliminates this on subsequent games.

// Current game_baord.zig public api:
//  - pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, numMines: u32, rand: std.Random) error{ OutOfMemory, TooManyMines, InvalidDimensions }!Self
//  - pub fn deinit(self: *const Self) void
//  - pub inline fn getBytesNeeded(width: u32, height: u32) u32
//  - pub inline fn getCell(self: *const Self, row: i32, col: i32) ?*const Cell
//  - pub inline fn getCellIndex(row: u32, col: u32, width: u32) u32
//  - pub fn revealCell(self: *Self, flagBitset: *const FlagBitset, team: u32, row: i32, col: i32) error{OutOfMemory}!RevealResult
//  - pub fn comptimeFormatInit(alloc: std.mem.Allocator, comptime fmt: []const u8) error{OutOfMemory}!Self

const std = @import("std");

const Self = @This();

// Change to reasonable maxes as changes
// pub const MAX_DIMENSION: u32 = 10_000;
// pub const MAX_TEAMS: u10 = ~@as(u10, 0);

width: usize,
height: usize,
revealed: []u64,
mines: []u64,
zeroCells: []u64,
cellsLeft: usize,
allocator: std.mem.Allocator,

// pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, numMines: usize, rand: std.Random) error{ OutOfMemory, TooManyMines, InvalidDimensions }!Self {
// }
