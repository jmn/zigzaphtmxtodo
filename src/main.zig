const std = @import("std");
const zap = @import("zap");

pub const ToDo = struct {
    id: u32,
    name: []const u8,
    isCompleted: bool,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var todos = std.ArrayList(ToDo).init(gpa.allocator());
const rand = std.crypto.random;

fn todoHandler(r: zap.SimpleRequest) void {
    if (r.method) |method| {
        std.debug.print("METHOD: {s}\n", .{method});
        if (std.mem.eql(u8, method, "DELETE")) {
            var paramOneStr: ?zap.FreeOrNot = null;
            r.parseQuery();

            var maybe_id = r.getParamStr("id", alloc, true) catch unreachable;
            if (maybe_id) |*s| {
                paramOneStr = s.*;
            }

            var text = paramOneStr.?.str;
            std.debug.print("ParseInt parsing {s} \n", .{text});
            const id = std.fmt.parseInt(i32, text, 10) catch |err| {
                std.debug.print("ParseInt failed {?} \n", .{err});
                return;
            };

            std.debug.print("ParseInt is {?} \n", .{id});
            const item_index = for (todos.items, 0..) |todo, index| {
                std.debug.print("looping over items {?} {?}\n", .{ todo, index });
                if (todo.id == id) break index;
            } else null;

            if (item_index) |idx| {
                _ = todos.swapRemove(idx);
            }

            std.log.info("index, {any} ", .{item_index});
        }

        if (std.mem.eql(u8, method, "POST")) {
            r.parseBody() catch |err| {
                std.log.err("Parse Body error: {any}. Expected if body is empty", .{err});
            };

            if (r.body) |body| {
                std.log.info("Body length is {any}\n", .{body.len});
            }

            // check for query parameters
            r.parseQuery();

            var param_count = r.getParamCount();
            std.log.info("param_count: {}", .{param_count});

            // iterate over all params as strings
            var strparams = r.parametersToOwnedStrList(alloc, false) catch unreachable;
            defer strparams.deinit();
            std.debug.print("\n", .{});
            if (r.query) |the_query| {
                std.debug.print("QUERY: {s}\n", .{the_query});
            }

            for (strparams.items) |kv| {
                std.log.info("ParamStr `{s}` is `{s}`", .{ kv.key.str, kv.value.str });

                if (std.mem.eql(u8, kv.key.str, "name")) {
                    todos.append(ToDo{ .id = rand.int(u32), .name = kv.value.str, .isCompleted = false }) catch |err| {
                        std.log.err("Parse Body error: {any}. Expected if body is empty", .{err});
                    };
                }
            }
        }
    }

    std.debug.print("Rendering template \n ", .{});

    const template =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><script src="https://unpkg.com/htmx.org@1.9.6"></script></head>
        \\<body>
        \\<h1>Todos</h1>
        \\<ul id="todos">
        \\{{#todos}}
        \\<li><input type="checkbox" {{#isCompleted}} checked {{/isCompleted}} />{{name}} | <button hx-delete="/todos?id={{id}}" hx-select="#todos" hx-target="#todos" hx-swap="outerHTML" type="button">Delete</button></li>
        \\{{/todos}}
        \\</ul>
        \\<form hx-post="/todos" hx-select="#todos" hx-swap="outerHTML" hx-target="#todos" hx-on::after-request="this.reset()">
        \\<input type="text" name="name"/>
        \\<button type="submit" >Save</button>
        \\</form>
        \\</body></html>
    ;

    const p = zap.mustacheData(template) catch |err| {
        std.log.err("Parse Body error: {any}. Expected if body is empty", .{err});
        return;
    };

    defer zap.mustacheFree(p);

    var todosData = .{ .todos = todos.items };

    const ret = zap.mustacheBuild(p, todosData);
    defer ret.deinit();

    if (ret.str()) |s| {
        r.sendBody(s) catch return;
    } else {
        r.sendBody("<html><body><h1>mustacheBuild() failed!</h1></body></html>") catch return;
    }
}

fn setup_routes(a: std.mem.Allocator) !void {
    routes = std.StringHashMap(zap.SimpleHttpRequestFn).init(a);
    try routes.put("/todos", todoHandler);
}

fn dispatch_routes(r: zap.SimpleRequest) void {
    // dispatch
    if (r.path) |the_path| {
        if (routes.get(the_path)) |foo| {
            foo(r);
            return;
        }
    }

    // or default
    r.sendBody(
        \\ <html><body><p>Hello</p></body></html>
    ) catch return;
}

var routes: std.StringHashMap(zap.SimpleHttpRequestFn) = undefined;
var alloc: std.mem.Allocator = undefined;

pub fn main() !void {
    var allocator = gpa.allocator();
    alloc = allocator;

    todos = std.ArrayList(ToDo).init(alloc);
    defer todos.deinit();

    try todos.append(ToDo{ .id = rand.int(u32), .name = "foo", .isCompleted = false });
    try todos.append(ToDo{ .id = rand.int(u32), .name = "bar", .isCompleted = false });
    try todos.append(ToDo{ .id = rand.int(u32), .name = "baz", .isCompleted = true });

    try setup_routes(allocator);

    var listener = zap.SimpleHttpListener.init(.{
        .port = 3000,
        .on_request = dispatch_routes,
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    // start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}
