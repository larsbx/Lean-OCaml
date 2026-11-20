// Experimental bounded checker for the shared migration benchmark fragment.
// All expression checking is Goose code. The os module supplies only file I/O,
// arguments and a monotonic clock. This executable has no admission authority.
import std;
import os;

const MAX_HEIGHT = 128;
const MAX_NODES = 2000000;
const CHECK_FUEL = 10000000;

// Stable semantic refusals are separate from parser/resource execution failures.
const E_SCOPE = 1;
const E_UNKNOWN = 2;
const E_DUPLICATE = 3;
const E_SORT = 4;
const E_FUNCTION = 5;
const E_MISMATCH = 6;
const E_LIMIT = 7;
const E_HEIGHT = 8;

fn error_name(code: i64) -> const u8[:] {
    match code {
        0 => "accepted", 1 => "Invalid_scope", 2 => "Unknown_constant",
        3 => "Duplicate_definition", 4 => "Expected_sort",
        5 => "Expected_function", 6 => "Type_mismatch",
        7 => "Limit_exceeded", 8 => "Height_limit", _ => "Internal_error"
    }
}

// a/b/c are numeric literals or topological node IDs. Original input node IDs
// are copied unchanged into each fresh batch arena. Caches never cross batches.
struct Node {
    tag: u8, a: i64 = 0, b: i64 = 0, c: i64 = 0,
    name: const u8[:] = "",
    height: i64 = 1, free: i64 = -1,
    normal: i64 = -1, inferred: i64 = -1, validated: bool = false,
}
struct Definition { name: const u8[:], ty: i64, value: i64 }
struct Binding { name: const u8[:], ty: i64, value: i64, inferred: i64 }
struct State {
    nodes: Node[>..]&, env: Binding[>..]&, context: i64[>..<]&,
    fuel: i64 = CHECK_FUEL, error: i64 = 0,
}

fn step(s: State&, depth: i64) -> bool {
    if s.error != 0 { return false; }
    if depth > MAX_HEIGHT { s.error = E_HEIGHT; return false; }
    if s.fuel <= 0 { s.error = E_LIMIT; return false; }
    s.fuel -= 1;
    return true;
}

fn make_node(s: State&, input: Node) -> i64 {
    if !step(s, 1) { return 0; }
    if s.nodes.len >= MAX_NODES { s.error = E_LIMIT; return 0; }
    var n = input;
    n.normal = -1;
    n.inferred = -1;
    n.height = 1;
    n.free = -1;
    n.validated = n.tag != 'c';
    if n.tag == 'v' { n.free = n.a; }
    if n.tag == 'a' || n.tag == 'l' || n.tag == 'p' {
        let a = s.nodes[n.a];
        let b = s.nodes[n.b];
        n.height = 1 + max(a.height, b.height);
        n.free = max(a.free, if n.tag == 'a' { b.free } else { b.free - 1 });
        n.validated = a.validated && b.validated;
    }
    if n.tag == 't' {
        let a = s.nodes[n.a];
        let b = s.nodes[n.b];
        let c = s.nodes[n.c];
        n.height = 1 + max(a.height, max(b.height, c.height));
        n.free = max(a.free, max(b.free, c.free - 1));
        n.validated = a.validated && b.validated && c.validated;
    }
    if n.height > MAX_HEIGHT { s.error = E_HEIGHT; return 0; }
    let result = s.nodes.len;
    s.nodes.push(n);
    return result;
}

fn find_binding(s: State&, name: const u8[:]) -> i64 {
    var i = s.env.len;
    while i > 0 {
        if !step(s, 1) { return -1; }
        i -= 1;
        if s.env[i].name == name { return i; }
    }
    return -1;
}

// Every constant occurrence is checked, including children erased by beta/zeta.
// A successful validation remains valid under append-only environments.
recursive fn validate(s: State&, id: i64, depth: i64) {
    if !step(s, depth) { return; }
    let n = s.nodes[id];
    if n.validated { return; }
    if n.tag == 'c' {
        if find_binding(s, n.name) < 0 && s.error == 0 { s.error = E_UNKNOWN; }
    } else if n.tag == 'a' || n.tag == 'l' || n.tag == 'p' {
        validate(s, n.a, depth + 1);
        validate(s, n.b, depth + 1);
    } else if n.tag == 't' {
        validate(s, n.a, depth + 1);
        validate(s, n.b, depth + 1);
        validate(s, n.c, depth + 1);
    }
    if s.error == 0 { s.nodes[id].validated = true; }
}

recursive fn lift(s: State&, id: i64, amount: i64, cutoff: i64, depth: i64) -> i64 {
    if !step(s, depth) { return 0; }
    let n = s.nodes[id];
    if n.free < cutoff || amount == 0 { return id; }
    if n.tag == 'v' {
        if n.a < cutoff { return id; }
        if n.a > 1000000 - amount { s.error = E_LIMIT; return 0; }
        return make_node(s, Node { tag: 'v', a: n.a + amount });
    }
    var a = n.a;
    var b = n.b;
    var c = n.c;
    if n.tag == 'a' || n.tag == 'l' || n.tag == 'p' {
        a = lift(s, n.a, amount, cutoff, depth + 1);
        b = lift(s, n.b, amount, cutoff + (if n.tag == 'a' { 0 } else { 1 }), depth + 1);
    } else if n.tag == 't' {
        a = lift(s, n.a, amount, cutoff, depth + 1);
        b = lift(s, n.b, amount, cutoff, depth + 1);
        c = lift(s, n.c, amount, cutoff + 1, depth + 1);
    } else { return id; }
    if a == n.a && b == n.b && c == n.c { return id; }
    return make_node(s, Node { tag: n.tag, a: a, b: b, c: c });
}

recursive fn substitute(s: State&, id: i64, replacement: i64, cutoff: i64, depth: i64) -> i64 {
    if !step(s, depth) { return 0; }
    let n = s.nodes[id];
    if n.free < cutoff { return id; }
    if n.tag == 'v' {
        if n.a < cutoff { return id; }
        if n.a == cutoff { return lift(s, replacement, cutoff, 0, 1); }
        return make_node(s, Node { tag: 'v', a: n.a - 1 });
    }
    var a = n.a;
    var b = n.b;
    var c = n.c;
    if n.tag == 'a' || n.tag == 'l' || n.tag == 'p' {
        a = substitute(s, n.a, replacement, cutoff, depth + 1);
        b = substitute(s, n.b, replacement, cutoff + (if n.tag == 'a' { 0 } else { 1 }), depth + 1);
    } else if n.tag == 't' {
        a = substitute(s, n.a, replacement, cutoff, depth + 1);
        b = substitute(s, n.b, replacement, cutoff, depth + 1);
        c = substitute(s, n.c, replacement, cutoff + 1, depth + 1);
    } else { return id; }
    if a == n.a && b == n.b && c == n.c { return id; }
    return make_node(s, Node { tag: n.tag, a: a, b: b, c: c });
}

recursive fn head(s: State&, input: i64, depth: i64) -> i64 {
    var id = input;
    loop {
        if !step(s, depth) { return 0; }
        let n = s.nodes[id];
        if n.tag == 'c' {
            let binding = find_binding(s, n.name);
            if binding < 0 { if s.error == 0 { s.error = E_UNKNOWN; } return 0; }
            id = s.env[binding].value;
        } else if n.tag == 't' {
            id = substitute(s, n.c, n.b, 0, 1);
        } else if n.tag == 'a' {
            let f = head(s, n.a, depth + 1);
            if s.error != 0 { return 0; }
            let fn_node = s.nodes[f];
            if fn_node.tag == 'l' { id = substitute(s, fn_node.b, n.b, 0, 1); }
            else if f == n.a { return id; }
            else { return make_node(s, Node { tag: 'a', a: f, b: n.b }); }
        } else { return id; }
    }
}

recursive fn normal(s: State&, id: i64, depth: i64) -> i64 {
    if !step(s, depth) { return 0; }
    if s.nodes[id].normal >= 0 { return s.nodes[id].normal; }
    let reduced = head(s, id, depth);
    if s.error != 0 { return 0; }
    let n = s.nodes[reduced];
    var result = reduced;
    if n.tag == 'a' || n.tag == 'l' || n.tag == 'p' {
        let a = normal(s, n.a, depth + 1);
        let b = normal(s, n.b, depth + 1);
        if a != n.a || b != n.b { result = make_node(s, Node { tag: n.tag, a: a, b: b }); }
    }
    if s.error == 0 { s.nodes[id].normal = result; }
    return result;
}

recursive fn equal(s: State&, left: i64, right: i64, depth: i64) -> bool {
    if !step(s, depth) { return false; }
    if left == right { return true; }
    let a = s.nodes[left];
    let b = s.nodes[right];
    if a.tag != b.tag { return false; }
    if a.tag == 's' || a.tag == 'v' { return a.a == b.a; }
    if a.tag == 'c' { return a.name == b.name; }
    if a.tag == 'a' || a.tag == 'l' || a.tag == 'p' {
        return equal(s, a.a, b.a, depth + 1) && equal(s, a.b, b.b, depth + 1);
    }
    if a.tag == 't' {
        return equal(s, a.a, b.a, depth + 1) && equal(s, a.b, b.b, depth + 1)
            && equal(s, a.c, b.c, depth + 1);
    }
    return false;
}

fn convertible(s: State&, left: i64, right: i64) -> bool {
    let a = normal(s, left, 1);
    let b = normal(s, right, 1);
    return s.error == 0 && equal(s, a, b, 1);
}

recursive fn infer(s: State&, id: i64, depth: i64) -> i64 {
    if !step(s, depth) { return 0; }
    let n = s.nodes[id];
    // Only closed syntax is cached: open typing depends on the binder context.
    if n.free < 0 && n.inferred >= 0 { return n.inferred; }
    var result = 0;
    if n.tag == 's' {
        if n.a >= 1000000 { s.error = E_LIMIT; return 0; }
        result = make_node(s, Node { tag: 's', a: n.a + 1 });
    } else if n.tag == 'v' {
        if n.a >= s.context.len { s.error = E_SCOPE; return 0; }
        result = lift(s, s.context[s.context.len - 1 - n.a], n.a + 1, 0, 1);
    } else if n.tag == 'c' {
        let binding = find_binding(s, n.name);
        if binding < 0 { if s.error == 0 { s.error = E_UNKNOWN; } return 0; }
        result = s.env[binding].ty;
    } else if n.tag == 'l' {
        sort_level(s, n.a, depth + 1);
        let mark = s.context.len;
        s.context.push(n.a);
        let body = infer(s, n.b, depth + 1);
        s.context.resize(mark);
        result = make_node(s, Node { tag: 'p', a: n.a, b: body });
    } else if n.tag == 'p' {
        let domain = sort_level(s, n.a, depth + 1);
        let mark = s.context.len;
        s.context.push(n.a);
        let codomain = sort_level(s, n.b, depth + 1);
        s.context.resize(mark);
        result = make_node(s, Node { tag: 's', a: if codomain == 0 { 0 } else { max(domain, codomain) } });
    } else if n.tag == 'a' {
        let fn_type = infer(s, n.a, depth + 1);
        let reduced = head(s, fn_type, 1);
        if s.error != 0 { return 0; }
        let fn_node = s.nodes[reduced];
        if fn_node.tag != 'p' { s.error = E_FUNCTION; return 0; }
        let arg_type = infer(s, n.b, depth + 1);
        if !convertible(s, arg_type, fn_node.a) {
            if s.error == 0 { s.error = E_MISMATCH; }
            return 0;
        }
        result = substitute(s, fn_node.b, n.b, 0, 1);
    } else if n.tag == 't' {
        sort_level(s, n.a, depth + 1);
        let value_type = infer(s, n.b, depth + 1);
        if !convertible(s, value_type, n.a) {
            if s.error == 0 { s.error = E_MISMATCH; }
            return 0;
        }
        let expanded = substitute(s, n.c, n.b, 0, 1);
        result = infer(s, expanded, depth);
    }
    if s.error == 0 && n.free < 0 { s.nodes[id].inferred = result; }
    return result;
}

recursive fn sort_level(s: State&, id: i64, depth: i64) -> i64 {
    let inferred = infer(s, id, depth);
    let reduced = head(s, inferred, 1);
    if s.error != 0 { return 0; }
    if s.nodes[reduced].tag != 's' { s.error = E_SORT; return 0; }
    return s.nodes[reduced].a;
}

fn check_definition(s: State&, d: Definition) -> i64 {
    s.error = 0;
    s.fuel = CHECK_FUEL;
    s.context.clear();
    if find_binding(s, d.name) >= 0 { return E_DUPLICATE; }
    if s.nodes[d.ty].free >= 0 || s.nodes[d.value].free >= 0 { return E_SCOPE; }
    validate(s, d.ty, 1);
    validate(s, d.value, 1);
    sort_level(s, d.ty, 1);
    let actual = infer(s, d.value, 1);
    let actual_normal = normal(s, actual, 1);
    if !convertible(s, actual_normal, d.ty) && s.error == 0 { s.error = E_MISMATCH; }
    if s.error != 0 { return s.error; }
    s.env.push(Binding { name: d.name, ty: d.ty, value: d.value, inferred: actual_normal });
    return 0;
}

fn execution_error(code: i64) {
    write_stderr("goose bounded checker: ");
    write_stderr(error_name(code));
    write_stderr("\n");
    exit(2);
}

fn import_nodes(s: State&, raw: const Node[:]) {
    for n in raw { make_node(s, n); }
    if s.error != 0 { execution_error(s.error); }
}

fn verify(s: State&, definitions: const Definition[:]) {
    if s.env.len != definitions.len { abort("verification: binding count changed"); }
    // Discard inferred/normal forms before the untimed re-inference. The same
    // implementation is a consistency control; cross-language tests are separate.
    for &n in s.nodes { n.inferred = -1; n.normal = -1; }
    for d, i in definitions {
        let binding = s.env[i];
        if binding.name != d.name || binding.ty != d.ty || binding.value != d.value {
            abort("verification: stored definition changed");
        }
        s.fuel = CHECK_FUEL;
        s.error = 0;
        s.context.clear();
        let actual = infer(s, d.value, 1);
        if !convertible(s, actual, d.ty) { abort("verification: inferred type mismatch"); }
        if !convertible(s, actual, binding.inferred) { abort("verification: saved type mismatch"); }
        if s.error != 0 { execution_error(s.error); }
    }
}

fn run_batch(raw: const Node[:], definitions: const Definition[:]) -> i64 {
    var nodes: Node[>..] = [];
    var env: Binding[>..] = [];
    var context: i64[>..<] = [];
    var s = State { nodes: nodes, env: env, context: context };
    let start = clock_ns();
    import_nodes(s, raw);
    for d in definitions {
        let outcome = check_definition(s, d);
        if outcome != 0 { execution_error(outcome); }
    }
    let stop = clock_ns();
    if stop <= start { abort("non-positive monotonic interval"); }
    verify(s, definitions);
    return stop - start;
}

fn refusal_control() {
    var nodes: Node[>..] = [];
    var env: Binding[>..] = [];
    var context: i64[>..<] = [];
    var s = State { nodes: nodes, env: env, context: context };
    let sort = make_node(s, Node { tag: 's', a: 1 });
    let outcome = check_definition(s, Definition { name: "benchmarkInvalid", ty: sort, value: sort });
    if outcome != E_MISMATCH || env.len != 0 { abort("refusal control failed"); }
}

fn check_only(raw: const Node[:], definitions: const Definition[:]) {
    var nodes: Node[>..] = [];
    var env: Binding[>..] = [];
    var context: i64[>..<] = [];
    var s = State { nodes: nodes, env: env, context: context };
    var outcomes: i64[>..] = [];
    import_nodes(s, raw);
    for d in definitions {
        let count = env.len;
        let outcome = check_definition(s, d);
        if outcome == E_LIMIT || outcome == E_HEIGHT || outcome == E_SCOPE { execution_error(outcome); }
        if outcome != 0 && env.len != count { abort("refusal mutated environment"); }
        outcomes.push(outcome);
    }
    var output: u8[>..] = [];
    format(output, "{\"engine\":\"goose-aot\",\"status\":\"checked\",\"outcomes\":[");
    for d, i in definitions {
        if i > 0 { format(output, ","); }
        format(output, "{\"name\":\"", d.name, "\",\"outcome\":\"", error_name(outcomes[i]), "\"}");
    }
    format(output, "],\"accepted\":", env.len, ",\"acceptance_authority\":false}");
    print(output);
}

fn parse_failure(message: const u8[:]) {
    write_stderr("goose benchmark parser: ");
    write_stderr(message);
    write_stderr("\n");
    exit(3);
}

fn natural(text: const u8[:]) -> i64 {
    if text.len == 0 { parse_failure("empty natural"); }
    for c in text { if c < '0' || c > '9' { parse_failure("invalid natural"); } }
    let n, ok = parse_int(text);
    if !ok || n < 0 || n > 1000000 { parse_failure("natural outside parser bound"); }
    return n;
}

fn simple_name(text: const u8[:]) {
    if text.len == 0 { parse_failure("empty name"); }
    for c in text {
        if !ascii::is_alnum(c) && c != '_' { parse_failure("invalid constant name"); }
    }
}

fn child(text: const u8[:], nodes: i64) -> i64 {
    let index = natural(text);
    if index >= nodes { parse_failure("node reference must precede its use"); }
    return index;
}

fn parse(text: const u8[:], nodes: Node[>..]&, definitions: Definition[>..]&) {
    if text.len == 0 || text[text.len - 1] != '\n' { parse_failure("missing final LF"); }
    let rows = split(text, '\n');
    if rows[0] != "lean-ocaml-benchmark-dag-v1" { parse_failure("unknown DAG schema"); }
    for row_index in 1..rows.len - 1 {
        let fields = split(rows[row_index], '\t');
        if fields.len == 0 { parse_failure("empty row"); }
        if fields[0] == "n" {
            if definitions.len != 0 || fields.len < 4 { parse_failure("invalid node position"); }
            if natural(fields[1]) != nodes.len { parse_failure("noncontiguous node index"); }
            if fields[2].len != 1 { parse_failure("invalid node tag"); }
            let tag = fields[2][0];
            var n = Node { tag: tag };
            if tag == 's' || tag == 'v' {
                if fields.len != 4 { parse_failure("invalid leaf arity"); }
                n.a = natural(fields[3]);
                if tag == 's' && n.a > 128 { parse_failure("sort exceeds parser bound"); }
            } else if tag == 'c' {
                if fields.len != 4 { parse_failure("invalid constant arity"); }
                simple_name(fields[3]);
                n.name = fields[3];
            } else if tag == 'a' || tag == 'l' || tag == 'p' {
                if fields.len != 5 { parse_failure("invalid binary arity"); }
                n.a = child(fields[3], nodes.len);
                n.b = child(fields[4], nodes.len);
            } else if tag == 't' {
                if fields.len != 6 { parse_failure("invalid let arity"); }
                n.a = child(fields[3], nodes.len);
                n.b = child(fields[4], nodes.len);
                n.c = child(fields[5], nodes.len);
            } else { parse_failure("unknown node tag"); }
            nodes.push(n);
            if nodes.len > 1000000 { parse_failure("too many nodes"); }
        } else if fields[0] == "d" {
            if fields.len != 4 { parse_failure("invalid definition arity"); }
            simple_name(fields[1]);
            definitions.push(Definition { name: fields[1], ty: child(fields[2], nodes.len),
                                          value: child(fields[3], nodes.len) });
            if definitions.len > 4096 { parse_failure("too many definitions"); }
        } else { parse_failure("invalid row tag"); }
    }
    if definitions.len == 0 { parse_failure("empty definition inventory"); }
}

fn main() {
    let argv = args();
    let only_check = argv.len == 3 && argv[1] == "--check";
    if !only_check && argv.len != 4 { parse_failure("usage: benchmark fixture workers iterations | --check fixture"); }
    let path = if only_check { argv[2] } else { argv[1] };
    var text: u8[>..] = [];
    if !read_file(path, text) { parse_failure("cannot read fixture"); }
    var raw: Node[>..] = [];
    var definitions: Definition[>..] = [];
    parse(text, raw, definitions);
    refusal_control();
    if only_check { check_only(raw, definitions); return; }
    let workers = natural(argv[2]);
    let iterations = natural(argv[3]);
    if workers != 1 || iterations < 1 || iterations > 100000 { parse_failure("workers=1 and iterations=1..100000 required"); }
    run_batch(raw, definitions); // One complete untimed warm-up.
    var elapsed = 0;
    for _ in iterations { elapsed += run_batch(raw, definitions); }
    print("{\"engine\":\"goose-aot\",\"status\":\"passed\",\"workers\":1,\"iterations\":", iterations,
          ",\"definitions\":", definitions.len, ",\"elapsed_ns\":", elapsed,
          ",\"per_batch_ns\":", elapsed / (iterations as f64),
          ",\"validated_batches\":", iterations, ",\"refusal_controls\":1,\"acceptance_authority\":false}");
}
