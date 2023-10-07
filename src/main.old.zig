const std = @import("std");
const zap = @import("zap");

fn on_request(r: zap.SimpleRequest) void {
    // Create a zig multiline mustache template
    const template =
        \\<html>
        \\<h1>* Users:</h1>
        \\ <body
        \\<<#users>>
        \\<<id>>.<<& name>> (<<name>>)
        \\<</users>>
        \\Nested: <<& nested.item >>.
        \\ </body>
        \\</html>
    ;

    if (r.path) |the_path| {
        std.debug.print("PATH: {s}\n", .{the_path});
    }

    if (r.query) |the_query| {
        std.debug.print("QUERY: {s}\n", .{the_query});
    }

    const p = zap.mustacheData(template) catch return;
    defer zap.mustacheFree(p);

    const User = struct {
        name: []const u8,
        id: isize,
    };

    const ret = zap.mustacheBuild(p, .{
        .users = [_]User{
            .{
                .name = "Rene",
                .id = 1,
            },
            .{
                .name = "Caro",
                .id = 6,
            },
        },
        .nested = .{
            .item = "nesting works",
        },
    });
    defer ret.deinit();

    if (r.setContentType(.TEXT)) {
        if (ret.str()) |s| {
            r.sendBody(s) catch return;
        } else {
            r.sendBody("<html><body><h1>mustacheBuild() failed!</h1></body></html>") catch return;
        }
    } else |err| {
        std.debug.print("Error while setting content type: {}\n", .{err});
    }
}

var dynamic_counter: i32 = 0;
fn dynamic_site(r: zap.SimpleRequest) void {
    dynamic_counter += 1;
    var buf: [128]u8 = undefined;
    const filled_buf = std.fmt.bufPrintZ(
        &buf,
        "<html><body><h1>Hello # {d} from DYNAMIC ZAP!!!</h1></body></html>",
        .{dynamic_counter},
    ) catch "ERROR";
    r.sendBody(filled_buf) catch return;
}

fn setup_routes(a: std.mem.Allocator) !void {
    routes = std.StringHashMap(zap.SimpleHttpRequestFn).init(a);
    try routes.put("/dynamic", dynamic_site);
    try routes.put("/f", on_request);
}

fn dispatch_routes(r: zap.SimpleRequest) void {
    // dispatch
    if (r.path) |the_path| {
        if (routes.get(the_path)) |foo| {
            foo(r);
            return;
        }
    }
    // or default: present menu
    r.sendBody(
        \\ <html>
        \\   <body>
        \\     <p><a href="/static">static</a></p>
        \\     <p><a href="/dynamic">dynamic</a></p>
        \\   </body>
        \\ </html>
    ) catch return;
}

var routes: std.StringHashMap(zap.SimpleHttpRequestFn) = undefined;

pub fn main() !void {
    try setup_routes(std.heap.page_allocator);
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
