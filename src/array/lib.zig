const std = @import("std");
pub const dict = @import("dict.zig");
pub const flat = @import("flat.zig");
pub const list = @import("list.zig");
pub const map = @import("map.zig");
pub const struct_ = @import("struct.zig");
pub const union_ = @import("union.zig");

fn isMapLike(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |s| s.is_tuple and s.fields.len == 2 and @typeInfo(s.fields[0].type) != .optional,
        else => false,
    };
}

test "is map like" {
    try std.testing.expectEqual(true, isMapLike(struct { []const u8, i32 }));
    try std.testing.expectEqual(true, isMapLike(struct { []const u8, ?i32 }));
    try std.testing.expectEqual(true, isMapLike(struct { i32, ?i32 }));
    try std.testing.expectEqual(false, isMapLike(struct { ?i32, i32 }));
    try std.testing.expectEqual(false, isMapLike(struct { i32, i32, i32 }));
}
fn Builder2(comptime ctx: type, comptime T: type) type {
    return switch (@typeInfo(ctx)) {
        .bool, .int, .float => flat.Builder(T),
        .pointer => |p| switch (p.size) {
            .slice => switch (p.child) {
                u8, ?u8 => flat.Builder(T),
                else => list.Builder(T),
            },
            else => @compileError("unsupported builder type " ++ @typeName(T)),
        },
        .array => |a| switch (a.child) {
            u8, ?u8 => flat.Builder(T),
            else => list.Builder(T),
        },
        .optional => |o| Builder2(o.child, T),
        .@"struct" => if (comptime isMapLike(ctx)) map.Builder(T) else struct_.Builder(T),
        .@"union" => union_.Builder(T),
        else => @compileError("unsupported builder type " ++ @typeName(T)),
    };
}

// Covenience builder for any non-dict array type
pub fn Builder(comptime T: type) type {
    return Builder2(T, T);
}

test {
    _ = @import("./array.zig");
    _ = @import("./flat.zig");
    _ = @import("./list.zig");
    _ = @import("./struct.zig");
    _ = @import("./union.zig");
    _ = @import("./dict.zig");
    _ = @import("./map.zig");
}
