const std = @import("std");
const Src = std.builtin.SourceLocation;

// check for a decl named tracy_enabled in root or build_options
pub const enabled = blk: {
    var build_enable: ?bool = null;
    var root_enable: ?bool = null;

    const root = @import("root");
    if (@hasDecl(root, "tracy_enabled")) {
        root_enable = @as(bool, root.tracy_enabled);
    }
    if (!std.builtin.is_test) {
        // Don't try to include build_options in tests.
        // Otherwise `zig test` doesn't work.
        const options = @import("build_options");
        if (@hasDecl(options, "tracy_enabled")) {
            build_enable = @as(bool, options.tracy_enabled);
        }
    }

    if (build_enable != null and root_enable != null) {
        if (build_enable.? != root_enable.?) {
            @compileError("root.tracy_enabled disagrees with build_options.tracy_enabled! Please remove one or make them match.");
        }
    }

    break :blk root_enable orelse (build_enable orelse false);
};

const debug_verify_stack_order = false;

usingnamespace if (enabled) tracy_full else tracy_stub;

const tracy_stub = struct {
    pub const ZoneCtx = struct {
        pub inline fn Text(self: ZoneCtx, text: []const u8) void {}
        pub inline fn Name(self: ZoneCtx, name: []const u8) void {}
        pub inline fn Value(self: ZoneCtx, value: u64) void {}
        pub inline fn End(self: ZoneCtx) void {}
    };

    pub inline fn InitThread() void { }
    pub inline fn SetThreadName(name: [*:0]const u8) void { }
    
    pub inline fn Zone(comptime src: Src) ZoneCtx { return .{}; }
    pub inline fn ZoneN(comptime src: Src, name: [*:0]const u8) ZoneCtx { return .{}; }
    pub inline fn ZoneC(comptime src: Src, color: u32) ZoneCtx { return .{}; }
    pub inline fn ZoneNC(comptime src: Src, name: [*:0]const u8, color: u32) ZoneCtx { return .{}; }
    pub inline fn ZoneS(comptime src: Src, depth: i32) ZoneCtx { return .{}; }
    pub inline fn ZoneNS(comptime src: Src, name: [*:0]const u8, depth: i32) ZoneCtx { return .{}; }
    pub inline fn ZoneCS(comptime src: Src, color: u32, depth: i32) ZoneCtx { return .{}; }
    pub inline fn ZoneNCS(comptime src: Src, name: [*:0]const u8, color: u32, depth: i32) ZoneCtx { return .{}; }

    pub inline fn Alloc(ptr: ?*const c_void, size: usize) void { }
    pub inline fn Free(ptr: ?*const c_void) void { }
    pub inline fn SecureAlloc(ptr: ?*const c_void, size: usize) void { }
    pub inline fn SecureFree(ptr: ?*const c_void) void { }
    pub inline fn AllocS(ptr: ?*const c_void, size: usize, depth: c_int) void { }
    pub inline fn FreeS(ptr: ?*const c_void, depth: c_int) void { }
    pub inline fn SecureAllocS(ptr: ?*const c_void, size: usize, depth: c_int) void { }
    pub inline fn SecureFreeS(ptr: ?*const c_void, depth: c_int) void { }

    pub inline fn AllocN(ptr: ?*const c_void, size: usize, name: [*:0]const u8) void { }
    pub inline fn FreeN(ptr: ?*const c_void, name: [*:0]const u8) void { }
    pub inline fn SecureAllocN(ptr: ?*const c_void, size: usize, name: [*:0]const u8) void { }
    pub inline fn SecureFreeN(ptr: ?*const c_void, name: [*:0]const u8) void { }
    pub inline fn AllocNS(ptr: ?*const c_void, size: usize, depth: c_int, name: [*:0]const u8) void { }
    pub inline fn FreeNS(ptr: ?*const c_void, depth: c_int, name: [*:0]const u8) void { }
    pub inline fn SecureAllocNS(ptr: ?*const c_void, size: usize, depth: c_int, name: [*:0]const u8) void { }
    pub inline fn SecureFreeNS(ptr: ?*const c_void, depth: c_int, name: [*:0]const u8) void { }

    pub inline fn Message(text: []const u8) void { }
    pub inline fn MessageL(text: [*:0]const u8) void { }
    pub inline fn MessageC(text: []const u8, color: u32) void { }
    pub inline fn MessageLC(text: [*:0]const u8, color: u32) void { }
    pub inline fn MessageS(text: []const u8, depth: c_int) void { }
    pub inline fn MessageLS(text: [*:0]const u8, depth: c_int) void { }
    pub inline fn MessageCS(text: []const u8, color: u32, depth: c_int) void { }
    pub inline fn MessageLCS(text: [*:0]const u8, color: u32, depth: c_int) void { }

    pub inline fn FrameMark() void { }
    pub inline fn FrameMarkNamed(name: [*:0]const u8) void { }
    pub inline fn FrameMarkStart(name: [*:0]const u8) void { }
    pub inline fn FrameMarkEnd(name: [*:0]const u8) void { }
    pub inline fn FrameImage(image: ?*const c_void, width: u16, height: u16, offset: u8, flip: c_int) void { }

    pub inline fn PlotF(name: [*:0]const u8, val: f64) void { }
    pub inline fn PlotU(name: [*:0]const u8, val: u64) void { }
    pub inline fn PlotI(name: [*:0]const u8, val: i64) void { }
    pub inline fn AppInfo(text: []const u8) void { }
};

const tracy_full = struct {
    const c = @cImport({
        @cDefine("TRACY_ENABLE", "");
        @cInclude("TracyC.h");
    });

    const has_callstack_support = @hasDecl(c, "TRACY_HAS_CALLSTACK") and @hasDecl(c, "TRACY_CALLSTACK");
    const callstack_enabled: c_int = if (has_callstack_support) c.TRACY_CALLSTACK else 0;

    threadlocal var stack_depth: if (debug_verify_stack_order) usize else u0 = 0;

    pub const ZoneCtx = struct {
        _zone: c.___tracy_c_zone_context,
        _token: if (debug_verify_stack_order) usize else void,

        pub inline fn Text(self: ZoneCtx, text: []const u8) void {
            if (debug_verify_stack_order) {
                if (stack_depth != self._token) {
                    std.debug.panic("Error: expected Value() at stack depth {} but was {}\n", .{self._token, stack_depth});
                }
            }
            c.___tracy_emit_zone_text(self._zone, text.ptr, text.len);
        }
        pub inline fn Name(self: ZoneCtx, name: []const u8) void {
            if (debug_verify_stack_order) {
                if (stack_depth != self._token) {
                    std.debug.panic("Error: expected Value() at stack depth {} but was {}\n", .{self._token, stack_depth});
                }
            }
            c.___tracy_emit_zone_name(self._zone, name.ptr, name.len);
        }
        pub inline fn Value(self: ZoneCtx, val: u64) void {
            if (debug_verify_stack_order) {
                if (stack_depth != self._token) {
                    std.debug.panic("Error: expected Value() at stack depth {} but was {}\n", .{self._token, stack_depth});
                }
            }
            c.___tracy_emit_zone_value(self._zone, val);
        }
        pub inline fn End(self: ZoneCtx) void {
            if (debug_verify_stack_order) {
                if (stack_depth != self._token) {
                    std.debug.panic("Error: expected End() at stack depth {} but was {}\n", .{self._token, stack_depth});
                }
                stack_depth -= 1;
            }
            c.___tracy_emit_zone_end(self._zone);
        }
    };

    inline fn initZone(comptime src: Src, name: ?[*:0]const u8, color: u32, depth: c_int) ZoneCtx {
        // Tracy uses pointer identity to identify contexts.
        // The `src` parameter being comptime ensures that
        // each zone gets its own unique global location for this
        // struct.
        const static = struct {
            var loc: c.___tracy_source_location_data = undefined;
        };
        static.loc = .{
            .name = name,
            .function = src.fn_name.ptr,
            .file = src.file.ptr,
            .line = src.line,
            .color = color,
        };

        const zone = if (has_callstack_support)
            c.___tracy_emit_zone_begin_callstack(&static.loc, depth, 1)
        else
            c.___tracy_emit_zone_begin(&static.loc, 1);

        if (debug_verify_stack_order) {
            stack_depth += 1;
            return ZoneCtx{ ._zone = zone, ._token = stack_depth };
        } else {
            return ZoneCtx{ ._zone = zone, ._token = {} };
        }
    }

    pub inline fn InitThread() void {
        c.___tracy_init_thread();
    }
    pub inline fn SetThreadName(name: [*:0]const u8) void {
        c.___tracy_set_thread_name(name);
    }

    pub inline fn Zone(comptime src: Src) ZoneCtx {
        return initZone(src, null, 0, callstack_enabled);
    }
    pub inline fn ZoneN(comptime src: Src, name: [*:0]const u8) ZoneCtx {
        return initZone(src, name, 0, callstack_enabled);
    }
    pub inline fn ZoneC(comptime src: Src, color: u32) ZoneCtx {
        return initZone(src, null, color, callstack_enabled);
    }
    pub inline fn ZoneNC(comptime src: Src, name: [*:0]const u8, color: u32) ZoneCtx {
        return initZone(src, name, color, callstack_enabled);
    }
    pub inline fn ZoneS(comptime src: Src, depth: i32) ZoneCtx {
        return initZone(src, null, 0, depth);
    }
    pub inline fn ZoneNS(comptime src: Src, name: [*:0]const u8, depth: i32) ZoneCtx {
        return initZone(src, name, 0, depth);
    }
    pub inline fn ZoneCS(comptime src: Src, color: u32, depth: i32) ZoneCtx {
        return initZone(src, null, color, depth);
    }
    pub inline fn ZoneNCS(comptime src: Src, name: [*:0]const u8, color: u32, depth: i32) ZoneCtx {
        return initZone(src, name, color, depth);
    }

    pub inline fn Alloc(ptr: ?*const c_void, size: usize) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_alloc_callstack(ptr, size, callstack_enabled, 0);
        } else {
            c.___tracy_emit_memory_alloc(ptr, size, 0);
        }
    }
    pub inline fn Free(ptr: ?*const c_void) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_free_callstack(ptr, callstack_enabled, 0);
        } else {
            c.___tracy_emit_memory_free(ptr, size, 0);
        }
    }
    pub inline fn SecureAlloc(ptr: ?*const c_void, size: usize) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_alloc_callstack(ptr, size, callstack_enabled, 1);
        } else {
            c.___tracy_emit_memory_alloc(ptr, size, 1);
        }
    }
    pub inline fn SecureFree(ptr: ?*const c_void) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_free_callstack(ptr, callstack_enabled, 1);
        } else {
            c.___tracy_emit_memory_free(ptr, size, 1);
        }
    }
    pub inline fn AllocS(ptr: ?*const c_void, size: usize, depth: c_int) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_alloc_callstack(ptr, size, depth, 0);
        } else {
            c.___tracy_emit_memory_alloc(ptr, size, 0);
        }
    }
    pub inline fn FreeS(ptr: ?*const c_void, depth: c_int) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_free_callstack(ptr, depth, 0);
        } else {
            c.___tracy_emit_memory_free(ptr, 0);
        }
    }
    pub inline fn SecureAllocS(ptr: ?*const c_void, size: usize, depth: c_int) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_alloc_callstack(ptr, size, depth, 1);
        } else {
            c.___tracy_emit_memory_alloc(ptr, size, 1);
        }
    }
    pub inline fn SecureFreeS(ptr: ?*const c_void, depth: c_int) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_free_callstack(ptr, depth, 1);
        } else {
            c.___tracy_emit_memory_free(ptr, 1);
        }
    }

    pub inline fn AllocN(ptr: ?*const c_void, size: usize, name: [*:0]const u8) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_alloc_callstack_named(ptr, size, callstack_enabled, 0, name);
        } else {
            c.___tracy_emit_memory_alloc_named(ptr, size, 0, name);
        }
    }
    pub inline fn FreeN(ptr: ?*const c_void, name: [*:0]const u8) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_free_callstack_named(ptr, callstack_enabled, 0, name);
        } else {
            c.___tracy_emit_memory_free_named(ptr, 0, name);
        }
    }
    pub inline fn SecureAllocN(ptr: ?*const c_void, size: usize, name: [*:0]const u8) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_alloc_callstack_named(ptr, size, callstack_enabled, 1, name);
        } else {
            c.___tracy_emit_memory_alloc_named(ptr, size, 1, name);
        }
    }
    pub inline fn SecureFreeN(ptr: ?*const c_void, name: [*:0]const u8) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_free_callstack_named(ptr, callstack_enabled, 1, name);
        } else {
            c.___tracy_emit_memory_free_named(ptr, 1, name);
        }
    }
    pub inline fn AllocNS(ptr: ?*const c_void, size: usize, depth: c_int, name: [*:0]const u8) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_alloc_callstack_named(ptr, size, depth, 0, name);
        } else {
            c.___tracy_emit_memory_alloc_named(ptr, size, 0, name);
        }
    }
    pub inline fn FreeNS(ptr: ?*const c_void, depth: c_int, name: [*:0]const u8) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_free_callstack_named(ptr, depth, 0, name);
        } else {
            c.___tracy_emit_memory_free_named(ptr, 0, name);
        }
    }
    pub inline fn SecureAllocNS(ptr: ?*const c_void, size: usize, depth: c_int, name: [*:0]const u8) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_alloc_callstack_named(ptr, size, depth, 1, name);
        } else {
            c.___tracy_emit_memory_alloc_named(ptr, size, 1, name);
        }
    }
    pub inline fn SecureFreeNS(ptr: ?*const c_void, depth: c_int, name: [*:0]const u8) void {
        if (has_callstack_support) {
            c.___tracy_emit_memory_free_callstack_named(ptr, depth, 1, name);
        } else {
            c.___tracy_emit_memory_free_named(ptr, 1, name);
        }
    }

    pub inline fn Message(text: []const u8) void {
        c.___tracy_emit_message(text.ptr, text.len, callstack_enabled);
    }
    pub inline fn MessageL(text: [*:0]const u8) void {
        c.___tracy_emit_messageL(text, color, callstack_enabled);
    }
    pub inline fn MessageC(text: []const u8, color: u32) void {
        c.___tracy_emit_messageC(text.ptr, text.len, color, callstack_enabled);
    }
    pub inline fn MessageLC(text: [*:0]const u8, color: u32) void {
        c.___tracy_emit_messageLC(text, color, callstack_enabled);
    }
    pub inline fn MessageS(text: []const u8, depth: c_int) void {
        const inner_depth: c_int = if (has_callstack_support) depth else 0;
        c.___tracy_emit_message(text.ptr, text.len, inner_depth);
    }
    pub inline fn MessageLS(text: [*:0]const u8, depth: c_int) void {
        const inner_depth: c_int = if (has_callstack_support) depth else 0;
        c.___tracy_emit_messageL(text, inner_depth);
    }
    pub inline fn MessageCS(text: []const u8, color: u32, depth: c_int) void {
        const inner_depth: c_int = if (has_callstack_support) depth else 0;
        c.___tracy_emit_messageC(text.ptr, text.len, color, inner_depth);
    }
    pub inline fn MessageLCS(text: [*:0]const u8, color: u32, depth: c_int) void {
        const inner_depth: c_int = if (has_callstack_support) depth else 0;
        c.___tracy_emit_messageLC(text, color, inner_depth);
    }

    pub inline fn FrameMark() void {
        c.___tracy_emit_frame_mark(null);
    }
    pub inline fn FrameMarkNamed(name: [*:0]const u8) void {
        c.___tracy_emit_frame_mark(name);
    }
    pub inline fn FrameMarkStart(name: [*:0]const u8) void {
        c.___tracy_emit_frame_mark_start(name);
    }
    pub inline fn FrameMarkEnd(name: [*:0]const u8) void {
        c.___tracy_emit_frame_mark_end(name);
    }
    pub inline fn FrameImage(image: ?*const c_void, width: u16, height: u16, offset: u8, flip: c_int) void {
        c.___tracy_emit_frame_image(image, width, height, offset, flip);
    }

    pub inline fn PlotF(name: [*:0]const u8, val: f64) void {
        c.___tracy_emit_plot(name, val);
    }
    pub inline fn PlotU(name: [*:0]const u8, val: u64) void {
        c.___tracy_emit_plot(name, @intToFloat(f64, val));
    }
    pub inline fn PlotI(name: [*:0]const u8, val: i64) void {
        c.___tracy_emit_plot(name, @intToFloat(f64, val));
    }
    pub inline fn AppInfo(text: []const u8) void {
        c.___tracy_emit_message_appinfo(text.ptr, text.len);
    }
};