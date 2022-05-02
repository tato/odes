const c = @cImport(@cInclude("raylib.h"));
pub usingnamespace c;

pub inline fn GetMousePositionV() @Vector(2, i64) {
    return .{ c.GetMouseX(), c.GetMouseY() };
}

pub inline fn GetScreenSizeV() @Vector(2, i64) {
    return .{ c.GetScreenWidth(), c.GetScreenHeight() };
}

pub inline fn GetDroppedFilesSlice() []const [*c]const u8 {
    var count: i32 = undefined;
    const files = c.GetDroppedFiles(&count);
    return files[0..@intCast(u32, count)];
}
