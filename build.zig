const std = @import("std");
const builtin = @import("builtin");
pub const name = "arrow";
const path = "src/lib.zig";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const arrow_module = b.addModule(.{ .root_source_file = b.path("src/lib.zig"), .target = target, .optimize = optimize });

    const flatbuffers_dep = b.dependency("flatbuffers-zig", .{
        .target = target,
        .optimize = optimize,
    });
    const lz4_module = b.dependency("lz4", .{
        .target = target,
        .optimize = optimize,
    }).module("lz4");

    const flatbuffers_module = flatbuffers_dep.module("flatbuffers");
    // Expose to zig dependents
    arrow_module.addImport("flatbuffers", flatbuffers_module);
    arrow_module.addImport("lz4", lz4_module);

    const lib = b.addLibrary(.{ .linkage = .dynamic, .name = "arrow-zig", .root_module = arrow_module });
    b.installArtifact(lib);

    const test_step = b.step("test", "Run library tests");
    const main_tests = b.addTest(.{ .root_module = arrow_module });
    const run_main_tests = b.addRunArtifact(main_tests);
    test_step.dependOn(&run_main_tests.step);

    const integration_test_step = b.step(
        "test-integration",
        "Run integration tests (requires Python 3 + pyarrow >= 10.0.0)",
    );
    const ffi_test = b.addSystemCommand(&[_][]const u8{ "python", "test_ffi.py" });
    ffi_test.step.dependOn(&run_main_tests.step);
    ffi_test.step.dependOn(b.getInstallStep());
    const ipc_test = b.addSystemCommand(&[_][]const u8{ "python", "test_ipc.py" });
    ipc_test.step.dependOn(&run_main_tests.step);
    integration_test_step.dependOn(&ipc_test.step);
    integration_test_step.dependOn(&ffi_test.step);

    // Unit tests from examples
    if (b.pkg_hash.len == 0) {
        var examples_dir = try std.fs.cwd().openDir("examples/", .{ .iterate = true });
        var examples_dir_iter = try examples_dir.walk(b.allocator);
        defer examples_dir_iter.deinit();

        while (try examples_dir_iter.next()) |entry| {
            switch (entry.kind) {
                .file => {
                    var parts = std.mem.splitScalar(u8, entry.basename, '.');
                    const file_name = parts.next().?;
                    const test_name = try std.fmt.allocPrint(b.allocator, "{s}_test", .{file_name});

                    // Path
                    const file_path = try std.fmt.allocPrint(b.allocator, "examples/{s}", .{entry.basename});
                    defer b.allocator.free(file_path);

                    // Create module and import arrow
                    const test_module = b.createModule(.{ .root_source_file = b.path(file_path), .target = target, .optimize = optimize });
                    test_module.addImport("arrow", arrow_module);
                    const sub_test_step = b.step(test_name, test_name);
                    const test_compile = b.addTest(.{ .root_module = test_module });
                    const test_run = b.addRunArtifact(test_compile);
                    const test_install = b.addInstallArtifact(test_compile, .{ .dest_dir = .{ .override = .{ .custom = "testdata" } }, .dest_sub_path = test_name });
                    sub_test_step.dependOn(&test_install.step);
                    sub_test_step.dependOn(&test_run.step);
                },
                else => @panic("No directories are currently being supported"),
            }
        }
        const all_examples_module = b.createModule(.{ .root_source_file = b.path("examples/all.zig"), .target = target, .optimize = optimize });
        all_examples_module.addImport("arrow", arrow_module);

        const build_arrays_module = b.createModule(.{ .root_source_file = b.path("examples/build_arrays.zig"), .target = target, .optimize = optimize });
        build_arrays_module.addImport("arrow", arrow_module);

        // const build_arrays_test_step = b.step("build_arrays_test", "Build Arrays");
        // const build_arrays_test = b.addTest(.{ .root_module = build_arrays_module });
        // b.installArtifact(build_arrays_test);
        // const run_build_arrays_test = b.addRunArtifact(build_arrays_test);
        // build_arrays_test_step.dependOn(&run_build_arrays_test.step);

        const example_test_step = b.step("test-examples", "Run example tests");
        const example_tests = b.addTest(.{ .root_module = all_examples_module });
        const run_example_tests = b.addRunArtifact(example_tests);
        example_test_step.dependOn(&run_example_tests.step);
    }
}
