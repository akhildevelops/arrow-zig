const std = @import("std");
const tags = @import("../tags.zig");

const RecordBatchError = error{
    NotStruct,
};
const Allocator = std.mem.Allocator;

// This exists to be able to nest arrays at runtime.
pub const Array = struct {
    const Self = @This();
    pub const buffer_alignment = 64;
    pub const Buffer = []align(buffer_alignment) u8;
    pub const Buffers = [3]Buffer;
    pub const Tag = tags.Tag;

    tag: Tag,
    name: [:0]const u8,
    allocator: Allocator,
    // TODO: remove this field, compute from tag and buffers
    length: usize,
    null_count: usize,
    // https://arrow.apache.org/docs/format/Columnar.html#buffer-listing-for-each-layout
    // Depending on layout stores validity, type_ids, offets, data, or indices.
    // You can tell how many buffers there are by looking at `tag.abiLayout().nBuffers()`
    buffers: Buffers = .{ &.{}, &.{}, &.{} },
    children: []*Array = &.{},

    pub fn init(allocator: Allocator) !*Self {
        return try allocator.create(Self);
    }

    pub fn deinitAdvanced(
        self: *Self,
        comptime free_children: bool,
        comptime free_buffers: bool,
    ) void {
        if (free_children) for (self.children) |c| c.deinitAdvanced(free_children, free_buffers);
        if (self.children.len > 0) self.allocator.free(self.children);

        if (free_buffers) for (self.buffers) |b| if (b.len > 0) self.allocator.free(b);
        self.allocator.destroy(self);
    }

    pub fn deinit(self: *Self) void {
        self.deinitAdvanced(true, true);
    }

    pub fn toRecordBatch(self: *Self, name: [:0]const u8) RecordBatchError!void {
        if (self.tag != .Struct) return RecordBatchError.NotStruct;
        // Record batches don't support nulls. It's ok to erase this because our struct impl saves null
        // info in the children arrays.
        // https://docs.rs/arrow-array/latest/arrow_array/array/struct.StructArray.html#comparison-with-recordbatch
        self.name = name;
        self.null_count = 0;
        self.tag.Struct.nullable = false;
        self.allocator.free(self.buffers[0]); // Free some memory.
        self.buffers[0].len = 0; // Avoid double free.
    }

    fn print2(self: *Self, depth: u8) void {
        const tab = (" " ** std.math.maxInt(u8))[0 .. depth * 2];
        std.debug.print("{s}Array \"{s}\": {any}\n", .{ tab, self.name, self.tag });
        std.debug.print("{s}  null_count: {d} / {d}\n", .{ tab, self.null_count, self.length });
        for (self.buffers, 0..) |b, i| {
            std.debug.print("{s}  buf{d}: {any}\n", .{ tab, i, b });
        }
        for (self.children) |c| {
            c.print2(depth + 1);
        }
    }

    pub fn print(self: *Self) void {
        self.print2(0);
    }
};

const MaskInt = std.bit_set.DynamicBitSet.MaskInt;

fn numMasks(comptime T: type, bit_length: usize) usize {
    return (bit_length + (@bitSizeOf(T) - 1)) / @bitSizeOf(T);
}

pub fn validity(allocator: Allocator, bit_set: *std.bit_set.DynamicBitSet, null_count: usize) !Array.Buffer {
    // Have to copy out for alignment until aligned bit masks land in std :(
    // https://github.com/ziglang/zig/issues/15600
    if (null_count == 0) {
        bit_set.deinit();
        return &.{};
    }
    const n_masks = numMasks(MaskInt, bit_set.unmanaged.bit_length);
    const n_mask_bytes = numMasks(u8, bit_set.unmanaged.bit_length);

    const copy = try allocator.alignedAlloc(u8, Array.buffer_alignment, n_mask_bytes);
    const maskInts: []MaskInt = bit_set.unmanaged.masks[0..n_masks];
    @memcpy(copy, std.mem.sliceAsBytes(maskInts)[0..n_mask_bytes]);
    bit_set.deinit();

    return copy;
}

// Dummy allocator
fn alloc(_: *anyopaque, _: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
    return null;
}
fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
    return false;
}
fn free(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize) void {}
fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
    return null;
}

pub const null_array = Array{
    .tag = .Null,
    .name = &.{},
    .allocator = Allocator{ .ptr = undefined, .vtable = &Allocator.VTable{ .alloc = alloc, .resize = resize, .free = free, .remap = remap } },
    .length = 0,
    .null_count = 0,
    .buffers = .{ &.{}, &.{}, &.{} },
    .children = &.{},
};

test "null array" {
    const n = null_array;
    try std.testing.expectEqual(@as(usize, 0), n.null_count);
}
