const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const heap = std.heap;
const math = std.math;
const meta = std.meta;
const debug = std.debug;

const rl = @import("raylib.zig");

const V2 = @Vector(2, f64);
const V2i = @Vector(2, i64);
inline fn v2(from: anytype) V2 {
    return switch (@TypeOf(from)) {
        f32, f64, comptime_float => @splat(2, @as(f64, from)),
        V2i => V2{ @intToFloat(f64, from[0]), @intToFloat(f64, from[1]) },
        rl.Vector2 => V2{ @floatCast(f64, from.x), @floatCast(f64, from.y) },
        else => @compileLog("Unsupported type " ++ @typeName(@TypeOf(from))),
    };
}
inline fn asRl(from: V2) rl.Vector2 {
    return .{
        .x = @floatCast(f32, from[0]),
        .y = @floatCast(f32, from[1]),
    };
}

pub fn main() void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};

    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(1920, 1080, "odes to the blue");
    rl.SetTargetFPS(60);

    defer rl.CloseWindow();

    var app = App.init(gpa.allocator());
    var assets = Assets.init(gpa.allocator());

    var last_mouse_position = rl.GetMousePositionV();
    var resizing_image_index: ?usize = null;

    while (!rl.WindowShouldClose()) {
        var arena = heap.ArenaAllocator.init(gpa.allocator());
        defer arena.deinit();

        if (rl.IsFileDropped()) {
            const files = rl.GetDroppedFilesSlice();
            defer rl.ClearDroppedFiles();

            for (files) |file| {
                const texture = rl.LoadTexture(file);
                rl.SetTextureFilter(texture, rl.TEXTURE_FILTER_BILINEAR);

                const texture_index = assets.textures.items.len;
                assets.textures.append(assets.gpa, texture) catch unreachable;

                app.addImage(.{
                    .texture_index = texture_index,
                    .cell = app.getPointedCell(),
                    .span = V2i{ 2, 2 },
                });
            }
        }

        if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_MIDDLE)) {
            app.camera -= rl.GetMousePositionV() - last_mouse_position;
        }
        last_mouse_position = rl.GetMousePositionV();

        if (rl.IsKeyPressed(rl.KEY_F2)) {
            app.debug.draw_grid = !app.debug.draw_grid;
        }

        var ui = Ui.init(arena.allocator());
        app.collectUi(&ui, &assets);

        var hovering_image_index: ?usize = null;

        const mouse_cursor = cursor: for (ui.image_resize_triangles.items) |tri, i| {
            const p0 = tri.p0 - v2(16.0); // top-left
            const p1 = tri.p0; // bottom-right
            const mouse = v2(rl.GetMousePositionV());

            const dist0 = @sqrt(@reduce(.Add, p0 * mouse));
            const dist1 = @sqrt(@reduce(.Add, p1 * mouse));

            if (@reduce(.And, mouse > p0) and @reduce(.And, mouse < p1) and dist0 < dist1) {
                hovering_image_index = i;
                break :cursor rl.MOUSE_CURSOR_RESIZE_NWSE;
            }
        } else rl.MOUSE_CURSOR_DEFAULT;
        rl.SetMouseCursor(mouse_cursor);

        if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
            if (hovering_image_index) |i| {
                resizing_image_index = i;
            }
        } else if (rl.IsMouseButtonReleased(rl.MOUSE_BUTTON_LEFT)) {
            if (resizing_image_index) |_| {
                const cell = app.getPointedCell();
                std.log.info("Released resize action on {d},{d}!", .{ cell[0], cell[1] });
                // TODO clip to nearest grid size
            }
        } else if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
            // TODO interactively update size of image
        }

        {
            rl.BeginDrawing();
            defer rl.EndDrawing();

            rl.ClearBackground(rl.LIGHTGRAY);
            rl.DrawFPS(10, 10);

            ui.draw(&assets);
        }
    }
}

const App = struct {
    gpa: mem.Allocator,
    images: std.ArrayListUnmanaged(ImageNode) = .{},
    camera: V2i = V2i{ 0, 0 },
    debug: struct {
        draw_grid: bool = false,
    } = .{},

    const grid_cell_size = V2i{ 180, 150 };
    const half_grid_cell_size = @divExact(grid_cell_size, V2i{ 2, 2 });

    fn init(gpa: mem.Allocator) App {
        return .{ .gpa = gpa };
    }

    fn deinit(app: *App) void {
        app.images.deinit(app.gpa);
        app.* = undefined;
    }

    fn addImage(app: *App, new_image: ImageNode) void {
        for (app.images.items) |*image| {
            if (meta.eql(image.cell, new_image.cell)) {
                // TODO leaking rl.Texture2D when I override the previous ImageNode
                image.* = new_image;
                return;
            }
        }
        app.images.append(app.gpa, new_image) catch unreachable;
    }

    fn getPointedCell(app: *const App) V2i {
        const norm_mouse = rl.GetMousePositionV() - @divFloor(rl.GetScreenSizeV(), V2i{ 2, 2 });
        const cell_center = app.camera + norm_mouse + half_grid_cell_size;
        return @divFloor(cell_center, grid_cell_size);
    }

    fn getCellCenter(app: *const App, cell: V2i) V2i {
        return cell * grid_cell_size - app.camera + @divFloor(rl.GetScreenSizeV(), V2i{ 2, 2 });
    }

    fn collectUi(app: *const App, ui: *Ui, assets: *const Assets) void {
        if (app.debug.draw_grid) {
            var cells_shown = @divFloor(rl.GetScreenSizeV(), App.grid_cell_size) + V2i{ 1, 1 };
            if (@rem(cells_shown[0], 2) == 1) cells_shown[0] += 1;
            if (@rem(cells_shown[1], 2) == 1) cells_shown[1] += 1;
            const half_cells_shown = @divExact(cells_shown, V2i{ 2, 2 });

            const frst_cell = @divFloor(app.camera, App.grid_cell_size) - half_cells_shown;
            const last_cell = @divFloor(app.camera, App.grid_cell_size) + half_cells_shown;

            var x = frst_cell[0];
            while (x <= last_cell[0]) : (x += 1) {
                const center = app.getCellCenter(V2i{ x, 0 });
                const x0 = @intCast(i32, center[0] - App.half_grid_cell_size[0]);
                ui.debug_grid_columns.ensureTotalCapacity(ui.arena, 0x100) catch unreachable;
                ui.debug_grid_columns.append(ui.arena, x0) catch unreachable;
            }
            var y = frst_cell[1];
            while (y <= last_cell[1]) : (y += 1) {
                const center = app.getCellCenter(V2i{ 0, y });
                const y0 = @intCast(i32, center[1] - App.half_grid_cell_size[1]);
                ui.debug_grid_rows.ensureTotalCapacity(ui.arena, 0x100) catch unreachable;
                ui.debug_grid_rows.append(ui.arena, y0) catch unreachable;
            }
        }

        for (app.images.items) |image, i| {
            const texture = &assets.textures.items[image.texture_index];
            const enclosing_space = v2(App.grid_cell_size * image.span) * v2(0.95);
            const texture_size = v2(V2i{ texture.width, texture.height });
            const scale = @reduce(.Min, enclosing_space / texture_size);

            const cell_center = v2(app.getCellCenter(image.cell));
            const scaled_texture_size = texture_size * v2(scale);
            const position = cell_center - scaled_texture_size * v2(0.5);

            ui.image_indices.append(ui.arena, i) catch unreachable;
            ui.image_positions.append(ui.arena, position) catch unreachable;
            ui.image_scales.append(ui.arena, scale) catch unreachable;

            const p0 = position + scaled_texture_size;
            const p1 = V2{ p0[0], p0[1] - 16.0 };
            const p2 = V2{ p0[0] - 16.0, p0[1] };
            ui.image_resize_triangles.append(ui.arena, .{ .p0 = p0, .p1 = p1, .p2 = p2 }) catch unreachable;
        }
    }
};

const ImageNode = struct {
    texture_index: usize,
    cell: V2i,
    span: V2i,
};

const Assets = struct {
    gpa: mem.Allocator,
    textures: std.ArrayListUnmanaged(rl.Texture) = .{},

    fn init(gpa: mem.Allocator) Assets {
        return .{ .gpa = gpa };
    }
};

const Ui = struct {
    arena: mem.Allocator,
    debug_grid_rows: std.ArrayListUnmanaged(i64) = .{},
    debug_grid_columns: std.ArrayListUnmanaged(i64) = .{},

    image_indices: std.ArrayListUnmanaged(usize) = .{},
    image_positions: std.ArrayListUnmanaged(V2) = .{},
    image_scales: std.ArrayListUnmanaged(f64) = .{},
    image_resize_triangles: std.ArrayListUnmanaged(ResizeTriangle) = .{},

    // p0 is bottom right, "p3" would be top left
    const ResizeTriangle = struct { p0: V2, p1: V2, p2: V2 };

    fn init(arena: mem.Allocator) Ui {
        return Ui{
            .arena = arena,
        };
    }

    fn draw(ui: *const Ui, assets: *const Assets) void {
        for (ui.debug_grid_rows.items) |y| {
            const _y = @intCast(i32, y);
            rl.DrawLine(0, _y, rl.GetScreenWidth(), _y, rl.BLUE);
        }
        for (ui.debug_grid_columns.items) |x| {
            const _x = @intCast(i32, x);
            rl.DrawLine(_x, 0, _x, rl.GetScreenHeight(), rl.BLUE);
        }
        for (ui.image_indices.items) |image_index, i| {
            const texture = assets.textures.items[image_index];
            const position: rl.Vector2 = blk: {
                const p = ui.image_positions.items[i];
                break :blk .{ .x = @floatCast(f32, p[0]), .y = @floatCast(f32, p[1]) };
            };
            const scale = ui.image_scales.items[i];
            rl.DrawTextureEx(texture, position, 0, @floatCast(f32, scale), rl.WHITE);
        }
        for (ui.image_resize_triangles.items) |tri| {
            rl.DrawTriangle(asRl(tri.p0), asRl(tri.p1), asRl(tri.p2), rl.RED);
        }
    }
};
