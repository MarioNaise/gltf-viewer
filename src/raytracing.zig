// Currently not used, only works with spheres yet
// https://www.gabrielgambetta.com/computer-graphics-from-scratch

const std = @import("std");

const zalgebra = @import("zalgebra");
const Vec3 = zalgebra.Vec3;
const Vec2 = zalgebra.Vec2;
const Mat3 = zalgebra.Mat3;

const Framebuffer = @import("Framebuffer.zig");

const BACKGROUND_COLOR = 0xFFFFFFFF;

const PROJECTION_PLANE_D = 1;
const VIEW_PORT = Vec2.new(1, 1);
const ORIGIN = Vec3.new(0, 0, 0);

const Sphere = struct {
    radius: f32,
    specular: f32,
    color: Framebuffer.Color,
    center: Vec3,
    reflective: f32,
};

const Light = struct { intensity: f32, type: union(enum) {
    ambient: struct {},
    point: struct {
        position: Vec3,
    },
    directional: struct {
        direction: Vec3,
    },
} };

const Camera = struct {
    position: Vec3,
    rotation: Vec3,
};

const SPHERES = [_]Sphere{
    .{
        .radius = 1.0,
        .color = 0xFF0000FF,
        .center = Vec3.new(0, -1, 3),
        .specular = 500,
        .reflective = 0.2,
    },
    .{
        .radius = 1.0,
        .color = 0x0000FFFF,
        .center = Vec3.new(2, 0, 4),
        .specular = 500,
        .reflective = 0.3,
    },
    .{
        .radius = 1.0,
        .color = 0x00FF00FF,
        .center = Vec3.new(-2, 0, 4),
        .specular = 10,
        .reflective = 0.4,
    },
    .{
        .radius = 5000,
        .color = 0xFFFF00FF,
        .center = Vec3.new(0, -5001, 0),
        .specular = 1000,
        .reflective = 0.5,
    },
};
const LIGHTS = [_]Light{
    .{ .type = .ambient, .intensity = 0.2 },
    .{ .type = .{ .point = .{ .position = Vec3.new(2, 1, 0) } }, .intensity = 0.6 },
    .{ .type = .{ .directional = .{ .direction = Vec3.new(1, 4, 4) } }, .intensity = 0.2 },
};

pub fn draw(fb: *Framebuffer, cam: Camera) void {
    const screen = Vec2.new(
        @as(f32, @floatFromInt(fb.width)),
        @as(f32, @floatFromInt(fb.height)),
    );
    const half_w = @divTrunc(@as(i32, @intCast(fb.width)), 2);
    const half_h = @divTrunc(@as(i32, @intCast(fb.height)), 2);

    var i = -half_w;
    while (i < half_w) : (i += 1) {
        var j = -half_h;
        while (j < half_h) : (j += 1) {
            const rot_mat = Mat3.fromEulerAngles(cam.rotation);
            const p = rot_mat.mulByVec3(canvasToViewport(i, j, screen.x(), screen.y()));
            const color = traceRay(
                cam.position,
                p,
                1,
                std.math.inf(f32),
                3,
            );
            fb.putPixel(.{ i, j }, color);
        }
    }
}

fn traceRay(o: Vec3, d: Vec3, t_min: f32, t_max: f32, recursion_depth: u8) Framebuffer.Color {
    const closest = closestIntersection(o, d, t_min, t_max);

    if (closest.@"0" == null)
        return BACKGROUND_COLOR;

    const sphere = closest.@"0".?;

    const p = o.add(d.scale(closest.@"1"));
    const n = p.sub(sphere.center).norm();
    const v = d.scale(-1);
    const scalar = @min(1, computeLighting(p, n, v, sphere.specular));

    var closest_color: [4]u8 = undefined;
    std.mem.writeInt(u32, &closest_color, sphere.color, .big);
    for (0..3) |i| {
        closest_color[i] = @as(u8, @trunc(@as(f32, std.math.clamp(closest_color[i] * scalar, 0, 255))));
    }

    if (recursion_depth <= 0 or sphere.reflective <= 0)
        return std.mem.readInt(u32, &closest_color, .big);

    const r = reflectRay(v, n);
    var reflected_color: [4]u8 = undefined;
    std.mem.writeInt(u32, &reflected_color, traceRay(p, r, 0.05, std.math.inf(f32), recursion_depth - 1), .big);

    var new_color: [4]u8 = .{255} ** 4;
    for (0..3) |i| {
        new_color[i] = @as(u8, @trunc(std.math.clamp(
            @as(f32, closest_color[i]) * (1 - sphere.reflective) + @as(f32, reflected_color[i]) * sphere.reflective,
            0,
            255,
        )));
    }
    return std.mem.readInt(u32, &new_color, .big);
}

fn computeLighting(p: Vec3, n: Vec3, v: Vec3, s: f32) f32 {
    var i: f32 = 0.0;

    var l: Vec3 = undefined;
    var t_max: f32 = undefined;

    for (LIGHTS) |light| {
        switch (light.type) {
            .ambient => {
                i += light.intensity;
                continue;
            },
            .point => |li| {
                l = li.position.sub(p);
                t_max = 1;
            },
            .directional => |li| {
                l = li.direction;
                t_max = std.math.inf(f32);
            },
        }
        // shadow check
        const shadow = closestIntersection(p, l, 0.001, t_max);
        if (shadow.@"0" != null) {
            continue;
        }

        // diffuse
        const n_dot_l = n.dot(l);
        if (n_dot_l > 0) {
            i += light.intensity * n_dot_l / (n.length() * l.length());
        }

        // specular
        if (s > 0) {
            const r = reflectRay(l, n);
            const r_dot_v = r.dot(v);
            if (r_dot_v > 0) {
                i += light.intensity * std.math.pow(f32, r_dot_v / (r.length() * v.length()), s);
            }
        }
    }
    return i;
}

fn reflectRay(r: Vec3, n: Vec3) Vec3 {
    return n.scale(2 * n.dot(r)).sub(r);
}

fn closestIntersection(o: Vec3, d: Vec3, t_min: f32, t_max: f32) struct { ?Sphere, f32 } {
    var closest_t = std.math.inf(f32);
    var closest_sphere: ?Sphere = null;

    for (SPHERES) |sphere| {
        const t = intersectRaySphere(o, d, sphere);
        if (t[0] >= t_min and t[0] <= t_max and t[0] < closest_t) {
            closest_t = t[0];
            closest_sphere = sphere;
        }
        if (t[1] >= t_min and t[1] <= t_max and t[1] < closest_t) {
            closest_t = t[1];
            closest_sphere = sphere;
        }
    }
    return .{ closest_sphere, closest_t };
}

fn intersectRaySphere(o: Vec3, d: Vec3, sphere: Sphere) [2]f32 {
    const r = sphere.radius;
    const co = Vec3.sub(o, sphere.center);

    const a = Vec3.dot(d, d);
    const b = 2 * Vec3.dot(co, d);
    const c = Vec3.dot(co, co) - r * r;

    const discriminant = b * b - 4 * a * c;
    if (discriminant < 0) {
        return .{ std.math.inf(f32), std.math.inf(f32) };
    }

    return .{
        (-b + std.math.sqrt(discriminant)) / (2 * a),
        (-b - std.math.sqrt(discriminant)) / (2 * a),
    };
}

fn canvasToViewport(x: i32, y: i32, width: f32, height: f32) Vec3 {
    return Vec3.new(
        @as(f32, @floatFromInt(x)) * VIEW_PORT.x() / width,
        @as(f32, @floatFromInt(y)) * VIEW_PORT.y() / height,
        PROJECTION_PLANE_D,
    );
}
