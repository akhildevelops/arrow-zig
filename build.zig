const std = @import("std");

pub const name = "arrow";
const path = "src/lib.zig";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const arrow_module = b.createModule(.{ .root_source_file = b.path("src/lib.zig"), .target = target, .optimize = optimize });

    // const flatbuffers_module = b.dependency("flatbufferz", .{
    //     .target = target,
    //     .optimize = optimize,
    // }).module("flatbufferz");

    // const lz4_module = b.dependency("lz4", .{
    //     .target = target,
    //     .optimize = optimize,
    // }).module("lz4");

    // Expose to zig dependents
    // arrow_module.addImport("flatbuffers", flatbuffers_module);
    // arrow_module.addImport("lz4", lz4_module);

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

    const all_examples_module = b.createModule(.{ .root_source_file = b.path("examples/all.zig"), .target = target, .optimize = optimize });
    all_examples_module.addImport("arrow", arrow_module);

    const build_arrays_module = b.createModule(.{ .root_source_file = b.path("examples/build_arrays.zig"), .target = target, .optimize = optimize });
    build_arrays_module.addImport("arrow", arrow_module);

    const build_arrays_test_step = b.step("build_arrays_test", "Build Arrays");
    const build_arrays_test = b.addTest(.{ .root_module = build_arrays_module });
    b.installArtifact(build_arrays_test);
    const run_build_arrays_test = b.addRunArtifact(build_arrays_test);
    build_arrays_test_step.dependOn(&run_build_arrays_test.step);
    const example_test_step = b.step("test-examples", "Run example tests");
    const example_tests = b.addTest(.{ .root_module = all_examples_module });
    const run_example_tests = b.addRunArtifact(example_tests);
    example_test_step.dependOn(&run_example_tests.step);
}
