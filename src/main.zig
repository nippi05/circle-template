const std = @import("std");
const builtin = @import("builtin");
const gl = @import("zgl");
const glfw = @import("zglfw");
const zm = @import("zmath");

const Circles = std.MultiArrayList(struct {
    position: [2]f32,
    speed: f32,
    radius: f32,
    color: [3]f32,
});

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

    var circles = Circles.empty;
    defer circles.deinit(gpa);
    const inital_circle_count = 1000;
    try circles.ensureUnusedCapacity(gpa, inital_circle_count);
    var i: usize = 0;
    while (i < inital_circle_count) : (i += 1) {
        circles.appendAssumeCapacity(.{ .position = .{ 2 * rand.float(f32) - 1, 2 * rand.float(f32) - 1 }, .color = randomColor(rand), .speed = 0.01, .radius = rand.float(f32) });
    }

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
    gl.bufferData(.array_buffer, [2]f32, circles.items(.position), .dynamic_draw);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, .float, false, 2 * @sizeOf(f32), 0);
    gl.vertexAttribDivisor(0, 1);

    const radiusVBO = gl.genBuffer();
    defer radiusVBO.delete();

    gl.bindBuffer(radiusVBO, .array_buffer);
    gl.bufferData(.array_buffer, f32, circles.items(.radius), .static_draw);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 1, .float, false, @sizeOf(f32), 0);
    gl.vertexAttribDivisor(1, 1);

    const colorVBO = gl.genBuffer();
    defer colorVBO.delete();

    gl.bindBuffer(colorVBO, .array_buffer);
    gl.bufferData(.array_buffer, [3]f32, circles.items(.color), .static_draw);
    gl.enableVertexAttribArray(2);
    gl.vertexAttribPointer(2, 3, .float, false, 3 * @sizeOf(f32), 0);
    gl.vertexAttribDivisor(2, 1);

    while (!window.shouldClose()) {
        glfw.pollEvents();
        if (window.getKey(.escape) == .press) {
            window.setShouldClose(true);
        }

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

fn randomColor(rand: std.Random) [3]f32 {
    return .{ rand.float(f32), rand.float(f32), rand.float(f32) };
}
