// JSONPath filters cannot run a request-supplied regex. The body matcher
// rejects match() and search() at configuration time and provides a
// separate RE2-style matching mode for regular expressions.
const DisabledPattern = struct {
    pub fn isMatch(_: DisabledPattern, _: []const u8) bool {
        return false;
    }
};

pub fn compile(_: []const u8) ?DisabledPattern {
    return null;
}
