pub fn valid(min_ms: u32, max_ms: u32) bool {
    return min_ms <= max_ms and max_ms <= 10_000;
}
