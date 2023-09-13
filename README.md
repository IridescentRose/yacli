<h1 align="center">yacli</h1>
<p align="center">Yet Another CLI Library (in Zig)</p>

## How do I use it?

Import the `yacli.zig` file:
```zig
const yacli = @import("yacli.zig");
```

Now define your subroutines:

```zig
fn version_subroutine(arg_it: anytype) !void {
    _ = arg_it;
    std.debug.print("Version 1\n", .{});
}

pub fn main() {
    // ...

    const help_string = 
        \\version   Prints version
        \\
    ;

    try yacli.parse_subroutines(allocator, help_string, .{
        version_subroutine,
    });
}
```

## Great but how do I get arguments?

Let's modify the previous program:

```zig
fn hello_subroutine(arg_it: anytype) !void {
    const help_string = 
        \\name=<str>    Name to print
        \\
    ;
    var args = yacli.parse_args(help_string, arg_it) catch return;

    std.debug.print("Hello, {s}!", .{args.name});
}

fn version_subroutine(arg_it: anytype) !void {
    _ = arg_it;
    std.debug.print("Version 1\n", .{});
}

pub fn main() {
    // ...

    const help_string = 
        \\add       Add two numbers      
        \\version   Prints version
        \\
    ;

    try yacli.parse_subroutines(allocator, help_string, .{
        hello_subroutine,
        version_subroutine,
    });
}
```

## Limitations

Currently the annotated type in the help string is not parsed yet -- everything is just a string.
