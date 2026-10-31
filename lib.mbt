// Public library facade.  Everything here is pure: no file system access, so
// the same API compiles for native, wasm-gc and JavaScript.  Hosts that want
// `include` expansion pass a loader callback.

///|
fn lib_view(view : StringView) -> String {
  String::from_iter(view.iter())
}

///|
fn lib_trim(text : String) -> String {
  lib_view(text.trim())
}

///|
fn lib_is_space(c : Char) -> Bool {
  c == ' ' || c == '\t'
}

///|
fn lib_include_target(line : String) -> String? {
  let text = lib_trim(line)
  if text.length() < 8 {
    return None
  }
  let head = lib_view(text[0:7])
  if head.to_lower() != "include" {
    return None
  }
  if !lib_is_space(
      match text.get_char(7) {
        Some(c) => c
        None => ' '
      },
    ) {
    return None
  }
  let mut start = -1
  let mut i = 8
  while i < text.length() {
    let c = match text.get_char(i) {
      Some(c) => c
      None => break
    }
    if c == '"' {
      start = i + 1
      break
    }
    i = i + 1
  }
  if start < 0 {
    return None
  }
  let mut end = start
  while end < text.length() {
    let c = match text.get_char(end) {
      Some(c) => c
      None => break
    }
    if c == '"' {
      return Some(lib_view(text[start:end]))
    }
    end = end + 1
  }
  None
}

///|
/// Returns the path named by an `include "path"` directive, or None when the
/// line is not an include.
pub fn include_target(line : String) -> String? {
  lib_include_target(line)
}

///|
fn lib_is_separator(c : Char) -> Bool {
  c == '/' || c == '\\'
}

///|
/// Return the parent directory using portable slash handling.
pub fn path_dirname(path : String) -> String {
  let mut i = path.length() - 1
  while i >= 0 {
    let c = match path.get_char(i) {
      Some(c) => c
      None => break
    }
    if lib_is_separator(c) {
      if i == 0 {
        return "/"
      }
      return lib_view(path[0:i])
    }
    i = i - 1
  }
  ""
}

///|
fn lib_normalize_path(input : String) -> String {
  let path = input.replace_all(old="\\", new="/")
  let absolute = match path.get_char(0) {
    Some(c) => c == '/'
    None => false
  }
  let parts : Array[String] = []
  for view in path.split("/") {
    let part = lib_view(view)
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 && parts[parts.length() - 1] != ".." {
        parts.pop() |> ignore
      } else if !absolute {
        parts.push(part)
      }
      continue
    }
    parts.push(part)
  }
  let sb = StringBuilder()
  if absolute {
    sb.write_string("/")
  }
  for i in 0..<parts.length() {
    if i > 0 {
      sb.write_string("/")
    }
    sb.write_string(parts[i])
  }
  sb.to_string()
}

///|
/// Resolve a relative include path against its containing directory.
pub fn path_join(base : String, relative : String) -> String {
  if relative.length() > 0 &&
    lib_is_separator(
      match relative.get_char(0) {
        Some(c) => c
        None => '/'
      },
    ) {
    return lib_normalize_path(relative)
  }
  if base == "" {
    lib_normalize_path(relative)
  } else {
    lib_normalize_path(base + "/" + relative)
  }
}

///|
/// Expanded text plus deterministic include failures. Repeated non-ancestor includes are allowed.
pub(all) struct ExpandedSource {
  source : String
  missing : Array[String]
  errors : Array[@ast.Diagnostic]
}

///|
struct IncludeFrame {
  file : String
  base : String
  lines : Array[String]
  mut index : Int32
}

///|
/// Pure request/response include walker shared by synchronous and asynchronous hosts.
/// Call next(), supply the requested file with provide(), then finish() after next returns None.
pub struct IncludeExpander {
  frames : Array[IncludeFrame]
  output : Array[String]
  missing : Array[String]
  errors : Array[@ast.Diagnostic]
  mut pending : (String, String, @ast.Loc)?
}

///|
/// Seeds the recursion stack with the normalized root filename.
pub fn IncludeExpander::new(
  file : String,
  base_dir : String,
  source : String,
) -> IncludeExpander {
  {
    frames: [
      {
        file: path_join("", file),
        base: base_dir,
        lines: source.split("\n").map(lib_view).to_array(),
        index: 0,
      },
    ],
    output: [],
    missing: [],
    errors: [],
    pending: None,
  }
}

///|
/// Returns the next path to load. Detects cycles before requesting host I/O.
pub fn IncludeExpander::next(self : IncludeExpander) -> String? {
  if self.pending is Some((path, _, _)) {
    return Some(path)
  }
  while self.frames.length() > 0 {
    let frame = self.frames[self.frames.length() - 1]
    if frame.index >= frame.lines.length() {
      self.frames.pop() |> ignore
      continue
    }
    let line = frame.lines[frame.index]
    frame.index += 1
    match include_target(line) {
      None => self.output.push(line)
      Some(relative) => {
        let path = path_join(frame.base, relative)
        let loc = @ast.Loc::new(frame.file, frame.index)
        if self.frames.any(fn(f) { f.file == path }) {
          self.errors.push(
            @ast.Diagnostic::new(
              "include.cycle",
              "Include cycle: " +
              self.frames.map(fn(f) { f.file }).join(" -> ") +
              " -> " +
              path,
              loc,
            ),
          )
        } else if self.frames.length() >= 1024 {
          self.errors.push(
            @ast.Diagnostic::new(
              "include.depth", "Include nesting exceeds 1024 files", loc,
            ),
          )
        } else {
          self.pending = Some((path, line, loc))
          return Some(path)
        }
      }
    }
  }
  None
}

///|
/// Supplies a requested file; None retains the directive and records include.missing.
pub fn IncludeExpander::provide(
  self : IncludeExpander,
  content : String?,
) -> Unit {
  if self.pending is Some((path, line, loc)) {
    self.pending = None
    match content {
      Some(source) =>
        self.frames.push({
          file: path,
          base: path_dirname(path),
          lines: source.split("\n").map(lib_view).to_array(),
          index: 0,
        })
      None => {
        self.missing.push(path)
        self.output.push(line)
        self.errors.push(
          @ast.Diagnostic::new(
            "include.missing",
            "Cannot read include: " + path,
            loc,
          ),
        )
      }
    }
  }
}

///|
/// Returns accumulated output and diagnostics after all requests have been served.
pub fn IncludeExpander::finish(self : IncludeExpander) -> ExpandedSource {
  {
    source: self.output.join("\n"),
    missing: self.missing,
    errors: self.errors,
  }
}

///|
/// Expands includes with a synchronous loader. Async hosts use the same walker directly.
pub fn expand_includes(
  source : String,
  base_dir : String,
  read : (String) -> String?,
  file~ : String = "<input>",
) -> ExpandedSource {
  let walker = IncludeExpander::new(file, base_dir, source)
  while walker.next() is Some(path) {
    walker.provide(read(path))
  }
  walker.finish()
}

///|
/// Parse, book and validate text without filesystem access; inspect returned errors before reporting balances.
pub fn check_source(
  file : String,
  source : String,
) -> @validation.ValidatedLedger {
  @validation.validate_ledger(@syntax.parse_source(file, source))
}

///|
/// Expand includes using the host callback, then validate the expanded ledger.
pub fn check_expanded(
  file : String,
  base_dir : String,
  source : String,
  read : (String) -> String?,
) -> @validation.ValidatedLedger {
  let expanded = expand_includes(source, base_dir, read, file~)
  let ledger = check_source(file, expanded.source)
  ledger.errors.append(expanded.errors)
  ledger
}

///|
/// Build account inventories and prices; at includes entries through that date.
pub fn realize(
  ledger : @validation.ValidatedLedger,
  at~ : @ast.Date? = None,
) -> @realization.RealizedLedger {
  @realization.realize(ledger, at~)
}

///|
/// Run the supported BQL subset; inspect QueryResult.error before consuming rows.
pub fn run_query(
  ledger : @validation.ValidatedLedger,
  statement : String,
  at~ : @ast.Date? = None,
) -> @query.QueryResult {
  @query.run_query(realize(ledger, at~), statement)
}

///|
/// Align posting amounts while preserving ledger semantics.
pub fn format_source(source : String) -> String {
  @format.format_source(source)
}

///|
/// Render the stable diagnostic code and original source location.
pub fn diagnostic_text(diagnostic : @ast.Diagnostic) -> String {
  diagnostic.loc.file +
  ":" +
  diagnostic.loc.line.to_string() +
  ": " +
  diagnostic.code +
  ": " +
  diagnostic.message
}
