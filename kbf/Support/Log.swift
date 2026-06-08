import os

/// Unified logging. Read with:
///   log show --last 2m --predicate 'subsystem == "com.ericjypark.kbf"' --info
enum Log {
    static let find = Logger(subsystem: "com.ericjypark.kbf", category: "find")
    static let click = Logger(subsystem: "com.ericjypark.kbf", category: "click")
}
