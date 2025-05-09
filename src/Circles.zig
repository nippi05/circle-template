const std = @import("std");

data: std.MultiArrayList(struct {
    position: [2]f32,
    speed: f32,
    color: [3]f32,
}),

const Self = @This();

pub fn init

pub fn move(self: *Self) void {
	for (self.data.get()) |value| { }
}
