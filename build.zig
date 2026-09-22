const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addModule("rrt", .{ .root_source_file = b.path("src/lib.zig"), .target = target, .optimize = optimize });
    const core = b.addExecutable(.{ .name = "rtt-core", .root_module = b.createModule(.{ .root_source_file = b.path("src/core_main.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "rrt", .module = lib }} }) });
    const cli = b.addExecutable(.{ .name = "rtt-cli", .root_module = b.createModule(.{ .root_source_file = b.path("src/cli_main.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "rrt", .module = lib }} }) });
    b.installArtifact(core);
    b.installArtifact(cli);
    const run_core = b.addRunArtifact(core);
    if (b.args) |args| run_core.addArgs(args);
    const s1 = b.step("run-core", "Starts rtt-core");
    s1.dependOn(&run_core.step);
    const run_cli = b.addRunArtifact(cli);
    if (b.args) |args| run_cli.addArgs(args);
    const s2 = b.step("run-cli", "Starts rtt-cli");
    s2.dependOn(&run_cli.step);
    const tests = b.addTest(.{ .root_module = lib });
    const run_tests = b.addRunArtifact(tests);
    const ts = b.step("test", "Runs unit tests");
    ts.dependOn(&run_tests.step);
    const fmt = b.addSystemCommand(&.{ "zig", "fmt", "--check", "src", "tests", "build.zig" });
    const fs = b.step("fmt-check", "Checks formatting");
    fs.dependOn(&fmt.step);
}
