const std = @import("std");
const builtin = std.builtin;

pub const String = []const u8;
pub const Subroutine = *const fn(arg: anytype) anyerror!void;
pub const SubroutineMap = struct {
    cmd_names: []const String,
    subroutines: []const Subroutine
};

/// Grab the number of lines 
fn get_line_count(comptime str: []const u8) usize {
    var count : usize = 0;
    for(str) |c| {
        if(c == '\n')
            count += 1;
    }

    return count;
}

/// Grab the names of the help string from first word of every line (does not strip)
fn get_names(comptime str: []const u8) [get_line_count(str)]String {
    const count = get_line_count(str);
    var array : [count]String = undefined;

    var i : usize = 0;
    var seq = std.mem.splitSequence(u8, str, "\n");
    while(i < count) : (i += 1) {
        const nstr = seq.next().?;
        var nseq = std.mem.splitSequence(u8, nstr, " ");

        array[i] = nseq.next().?;
    }

    return array;
}

/// Get the length of a given comptime tuple
fn get_tuple_len(comptime args: anytype) usize {
    return @typeInfo(@TypeOf(args)).Struct.fields.len;
}

/// Grab the argument after an equal sign 
fn get_seq_str(arg: []const u8) []const u8 {
    var seq = std.mem.splitSequence(u8, arg, "=");
    _ = seq.next().?;

    return seq.next().?;
}

/// Grab the args tuple into a subroutine list at compile time
fn comptime_args(comptime args: anytype) [get_tuple_len(args)]Subroutine {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);

    if(args_type_info != .Struct) 
        @compileError("Expected struct or tuple");

    const fields_info = args_type_info.Struct.fields;
    var subroutines : [fields_info.len]Subroutine = undefined;
    var i : usize = 0;

    // Grab each field as a new subroutine
    while(i < fields_info.len) : (i += 1) {
        subroutines[i] = @field(args, fields_info[i].name);
    }

    return subroutines;
}

/// Strips the decorators off of a given name -- reduces to just a name
/// E.G. `[opt]=<str>` returns just `opt`
fn strip_decoration(comptime str: []const u8) []const u8 {
    var copy = str;

    for(str, 0..) |c, i| {
        if(c == '=') {
            copy = str[0..i];
            break;
        }
    }

    if(copy[0] == '[')
        copy = copy[1..copy.len - 1];
    
    return copy;
}

/// Strip all decorations from a list of strings
fn strip_all(comptime str: []const String) []const String {
    var copy : [str.len]String = undefined;

    inline for(str, 0..) |v, i| {
        copy[i] = comptime strip_decoration(v);
    }

    return copy[0..];
}

/// Parses the type from a given help string -- this is a struct which holds a bunch of arguments
fn get_type(comptime help_string: []const u8) type {
    const names = get_names(help_string);
    var fields: [names.len]builtin.Type.StructField = undefined;

    // Turn each string into a field
    for(names, 0..) |str, v| {
        var opt : bool = false;
        var boolean : bool = false;
        var string : bool = false;

        if(str[0] == '[') // It's an optional!
            opt = true;
        
        var name : []const u8 = undefined;

        var i : usize = 0;
        while(i < str.len) : (i += 1) {
            if(opt and str[i] == ']') { 
                name = str[1..i];
                break; 
            } else if (str[i] == '=') {
                name = str[0..i];
                string = true;
                break;
            }
        }

        if(i == str.len) {
            name = str;
            boolean = true;
        } else {
            i += 1;
            if(i < str.len and str[i] == '=') {
                string = true;
            }
        }
            
        const default_value = if (!opt) 
                if (boolean and !string) 
                    @as(bool, false) 
                else 
                    @as([]const u8, "") 
             else 
                if (boolean and !string) 
                    @as(?bool, null)
                else 
                    @as(?[]const u8, null);

        var term_name : [name.len:0]u8 = [_:0]u8{0} ** (name.len);

        for(name, 0..) |c, j| {
            term_name[j] = c;
        }

        fields[v] = .{
            .name = &term_name,
            .type = @TypeOf(default_value),
            .default_value = @ptrCast(&default_value),
            .is_comptime = false,
            .alignment = @alignOf(@TypeOf(default_value)),
        };
    }

    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .fields = fields[0..],
            .decls = &.{},
            .is_tuple = false,
        }
    });
}

/// Parses args for a command (or subroutine) into a struct
/// `help_string` is the expected format string
/// `arg_it` is the argument iterator
pub fn parse_args(comptime help_string: []const u8, arg_it: anytype) !get_type(help_string) {
    const T = comptime get_type(help_string);
    const name_raw = comptime get_names(help_string);
    const names = comptime strip_all(name_raw[0..]);

    // Initialize to defaults -- don't use undefined here!
    var value = T{};
    const ArgsType = @TypeOf(value);
    const args_type_info = @typeInfo(ArgsType);

    if(args_type_info != .Struct) 
        @compileError("Expected struct or tuple");

    var curr_arg = arg_it.next();
    while (curr_arg != null) : (curr_arg = arg_it.next()) {
        var found : bool = false;
        inline for(names) |field_name| {
            if(std.mem.containsAtLeast(u8, curr_arg.?, 1, field_name)) {
                found = true;
                // Switch over the type of the field
                switch (@TypeOf(@field(value, field_name))) {
                    bool, ?bool => {
                        @field(value, field_name) = true; // Using @field() = x does proper assignment
                    },
                    []const u8, ?[]const u8 => {
                        @field(value, field_name) = get_seq_str(curr_arg.?); // Using @field() = x does proper assignment
                    },
                    else => @compileError("Invalid Type!")
                }
            }
        }

        if(!found) {
            std.debug.print("Error: Unknown argument {s}\n", .{curr_arg.?});
            std.debug.print("{s}", .{help_string});
            return error.UnknownArgument;
        }
    }

    const fields_info = args_type_info.Struct.fields;
    inline for (fields_info) |fi| {
        const field = @field(value, fi.name);
        switch(@TypeOf(field)) {
            []const u8 => {
                if(field.len == 0) {
                    std.debug.print("{s}", .{help_string});
                    return error.UnfulfilledArgument;
                }
            },
            else => {}
        }
    } 

    return value;
}

/// Parse a subroutine table from an allocator, help string, and tuple
/// The help string must be properly formatted insofar as the first word of each line is the command name
/// The args must be in the correct order as the help_string, as there's no way to "match" function names
pub fn parse_subroutines(allocator: std.mem.Allocator, comptime help_string: []const u8, comptime args: anytype) !void {
    @setEvalBranchQuota(1000000000);

    // Iterator
    var arg_it = std.process.argsWithAllocator(allocator) catch unreachable;

    // Skip past the first argument (executable name)
    _ = arg_it.skip();

    // Sub command argument
    const sub_cmd = arg_it.next();

    // If there is no subcommand quit
    if(sub_cmd == null) {
        std.debug.print("{s}", .{help_string});
        return;
    }

    // Check if we hit any of the matches
    var ran : bool = false;

    const subroutines = comptime comptime_args(args);

    // Generate the map
    const map = SubroutineMap {
        .cmd_names = &comptime get_names(help_string),
        .subroutines = &subroutines,
    };

    // Match all
    inline for(map.cmd_names, map.subroutines) |cmd, sub| {
        if(std.mem.eql(u8, cmd, sub_cmd.?)) {
            ran = true;
            // Found: execute
            try sub(&arg_it);
        }
    }

    // If no match, we return
    if(!ran) {
        std.debug.print("{s}", .{help_string});
        return;
    }
}