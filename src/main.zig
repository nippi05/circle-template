const std = @import("std");
const builtin = @import("builtin");

const gl = @import("zgl");
const glfw = @import("zglfw");
const zm = @import("zmath");
const ztracy = @import("ztracy");

const Circle = struct {
    position: [2]f32,
    velocity: [2]f32,
    radius: f32,
    color: [3]f32,
};

const Circles = std.MultiArrayList(Circle);

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        if (builtin.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var prng = std.Random.DefaultPrng.init(0);
    const rand = prng.random();

    const max_circle_count = 100_000;
    var circles = Circles.empty;
    defer circles.deinit(gpa);
    try circles.ensureTotalCapacity(gpa, max_circle_count);
    circles.appendAssumeCapacity(newCircle(rand));

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 5);
    glfw.windowHint(.opengl_profile, @intFromEnum(glfw.OpenGLProfile.opengl_core_profile));

    const window_dimensions = .{ .width = 800, .height = 800 };
    const window = try glfw.Window.create(window_dimensions.width, window_dimensions.height, "learnopengl", null);
    defer window.destroy();

    glfw.makeContextCurrent(window);

    const proc: glfw.GlProc = undefined;
    try gl.loadExtensions(proc, glfwGetProcAddress);

    const shader_program = shader_program: {
        const vertex_shader = gl.createShader(.vertex);
        defer gl.deleteShader(vertex_shader);
        gl.shaderSource(vertex_shader, 1, &.{@embedFile("shaders/vertex.glsl")});
        gl.compileShader(vertex_shader);
        verifyOk(@intFromEnum(vertex_shader), .shader);

        const fragment_shader = gl.createShader(.fragment);
        defer gl.deleteShader(fragment_shader);
        gl.shaderSource(fragment_shader, 1, &.{@embedFile("shaders/fragment.glsl")});
        gl.compileShader(fragment_shader);
        verifyOk(@intFromEnum(fragment_shader), .shader);

        const constructing_program = gl.createProgram();
        gl.attachShader(constructing_program, vertex_shader);
        gl.attachShader(constructing_program, fragment_shader);
        gl.linkProgram(constructing_program);
        verifyOk(@intFromEnum(constructing_program), .program);
        break :shader_program constructing_program;
    };
    defer gl.deleteProgram(shader_program);

    const vao = gl.genVertexArray();
    gl.bindVertexArray(vao);
    defer gl.deleteVertexArray(vao);

    const positionsVBO = gl.genBuffer();
    defer positionsVBO.delete();

    gl.bindBuffer(positionsVBO, .array_buffer);
    gl.bufferUninitialized(.array_buffer, [2]f32, max_circle_count, .dynamic_draw);
    gl.bufferSubData(.array_buffer, 0, [2]f32, circles.items(.position));
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, .float, false, 2 * @sizeOf(f32), 0);
    gl.vertexAttribDivisor(0, 1);

    const radiusVBO = gl.genBuffer();
    defer radiusVBO.delete();

    gl.bindBuffer(radiusVBO, .array_buffer);
    gl.bufferUninitialized(.array_buffer, f32, max_circle_count, .dynamic_draw);
    gl.bufferSubData(.array_buffer, 0, f32, circles.items(.radius));
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 1, .float, false, @sizeOf(f32), 0);
    gl.vertexAttribDivisor(1, 1);

    const colorVBO = gl.genBuffer();
    defer colorVBO.delete();

    gl.bindBuffer(colorVBO, .array_buffer);
    gl.bufferUninitialized(.array_buffer, [3]f32, max_circle_count, .dynamic_draw);
    gl.bufferSubData(.array_buffer, 0, [3]f32, circles.items(.color));
    gl.enableVertexAttribArray(2);
    gl.vertexAttribPointer(2, 3, .float, false, 3 * @sizeOf(f32), 0);
    gl.vertexAttribDivisor(2, 1);

    while (!window.shouldClose()) {
        const frame_zone = ztracy.ZoneN(@src(), "frame");
        defer frame_zone.End();

        const poll_events_zone = ztracy.ZoneN(@src(), "poll_events");
        glfw.pollEvents();

        if (window.getKey(.escape) == .press) {
            window.setShouldClose(true);
        }
        poll_events_zone.End();

        // Update physics
        const physics_zone = ztracy.ZoneN(@src(), "physics");
        for (circles.items(.position), circles.items(.velocity)) |*position, velocity| {
            position[0] += velocity[0];
            position[1] += velocity[1];
        }
        var new_count: usize = 0;
        for (circles.items(.position), 0..) |position, i| {
            const clip_distance = 1;
            if (position[0] * position[0] + position[1] * position[1] > clip_distance * clip_distance) {
                new_count += 1;
                circles.set(i, newCircle(rand));
            }
        }
        const previous_length = circles.len;
        if (previous_length + new_count > max_circle_count) return error.TooManyCircles;
        var i: usize = 0;
        while (i < new_count) : (i += 1) {
            circles.appendAssumeCapacity(newCircle(rand));
        }
        physics_zone.End();
        // Write new positions
        const buffer_writing_zone = ztracy.ZoneN(@src(), "buffer_writing");
        gl.bindBuffer(positionsVBO, .array_buffer);
        gl.bufferSubData(.array_buffer, 0, [2]f32, circles.items(.position));

        // Partial updates
        if (new_count > 0) {
            gl.bindBuffer(colorVBO, .array_buffer);
            gl.bufferSubData(.array_buffer, 3 * previous_length * @sizeOf(f32), [3]f32, circles.items(.color)[previous_length..]);
            gl.bindBuffer(radiusVBO, .array_buffer);
            gl.bufferSubData(.array_buffer, previous_length * @sizeOf(f32), f32, circles.items(.radius)[previous_length..]);
        }
        buffer_writing_zone.End();

        const drawing_zone = ztracy.ZoneN(@src(), "drawing");
        defer drawing_zone.End();
        gl.clearColor(0.2, 0.3, 0.3, 1.0);
        gl.clear(.{ .color = true });

        gl.useProgram(shader_program);
        gl.drawArraysInstanced(.triangles, 0, 3, circles.len);

        window.swapBuffers();
    }
}

fn glfwGetProcAddress(p: glfw.GlProc, proc: [:0]const u8) ?gl.binding.FunctionPointer {
    _ = p;
    return glfw.getProcAddress(proc);
}

fn verifyOk(id: c_uint, kind: enum { shader, program }) void {
    const allocator = std.heap.page_allocator;
    const success = if (kind == .shader) gl.getShader(@enumFromInt(id), .compile_status) else gl.getProgram(@enumFromInt(id), .link_status);
    if (success != 1) { // I HATE C ERROR HANDLING
        @branchHint(.cold);
        const message = if (kind == .shader) gl.getShaderInfoLog(@enumFromInt(id), allocator) catch unreachable else gl.getProgramInfoLog(@enumFromInt(id), allocator) catch unreachable;
        std.log.err("Failed to compile a {s} with message: \n{s}\n", .{ @tagName(kind), message });
        unreachable; // Don't continue
    }
}

fn newCircle(rand: std.Random) Circle {
    const velocity = rand.float(f32) * 0.01;
    const angle = rand.float(f32) * 2 * std.math.pi;
    return .{
        .position = .{ 0, 0 },
        .color = .{ rand.float(f32), rand.float(f32), rand.float(f32) },
        .radius = 0.1 + 0.1 * rand.float(f32),
        .velocity = .{ velocity * std.math.cos(angle), velocity * std.math.sin(angle) },
    };
}
