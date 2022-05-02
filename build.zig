const std = @import("std");

const rl = @import("raylib/src/build.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("odes", "source/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    var raylib = rl.addRaylib(exe.builder, exe.target);

    for (raylib.link_objects.items) |*link_object| {
        const LinkObject = std.build.LibExeObjStep.LinkObject;
        const loc: *[]const []const u8 = switch (link_object.*) {
            LinkObject.c_source_files => |c_source_files| &c_source_files.flags,
            LinkObject.c_source_file => |c_source_file| &c_source_file.args,
            else => continue,
        };

        var my_raylib_flags = std.ArrayList([]const u8).init(b.allocator);
        my_raylib_flags.appendSlice(loc.*) catch unreachable;
        my_raylib_flags.append("-DSUPPORT_FILEFORMAT_BMP") catch unreachable;
        my_raylib_flags.append("-DSUPPORT_FILEFORMAT_JPG") catch unreachable;
        loc.* = my_raylib_flags.items;
    }

    exe.addIncludeDir("raylib/src");
    exe.linkLibrary(raylib);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("source/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
