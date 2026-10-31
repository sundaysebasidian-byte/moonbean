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
pub fn path_dirname(path : String) -> String {
  let mut i = path.length() - 1
  while i >= 0 {
    let c = match path.get_char(i) {
      Some(c) => c
      None => break
    }
    if lib_is_separator(c) {
      return lib_view(path[0:i])
    }
    i = i - 1
  }
  ""
}

///|
fn lib_normalize_path(path : String) -> String {
  let parts : Array[String] = []
  for view in path.split("/") {
    let part = lib_view(view)
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 && parts[parts.length() - 1] != ".." {
        parts.pop() |> ignore
      } else {
        parts.push(part)
      }
      continue
    }
    parts.push(part)
  }
  let sb = StringBuilder()
  for i in 0..<parts.length() {
    if i > 0 {
      sb.write_string("/")
    }
    sb.write_string(parts[i])
  }
  sb.to_string()
}

///|
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
pub(all) struct ExpandedSource {
  source : String
  missing : Array[String]
}

///|
fn lib_expand_into(
  source : String,
  base : String,
  read : (String) -> String?,
  missing : Array[String],
  lines : Array[String],
) -> Unit {
  for view in source.split("\n") {
    let line = lib_view(view)
    match lib_include_target(line) {
      Some(relative) => {
        let path = path_join(base, relative)
        match read(path) {
          Some(included) =>
            lib_expand_into(included, path_dirname(path), read, missing, lines)
          None => {
            missing.push(path)
            lines.push(line)
          }
        }
      }
      None => lines.push(line)
    }
  }
}

///|
/// Expands `include "path"` directives recursively.  `read` receives a path
/// joined to `base_dir` (or to the including file's directory) and returns the
/// file content, or None when the file cannot be read.  Missing paths are
/// reported separately and the include line is kept.
pub fn expand_includes(
  source : String,
  base_dir : String,
  read : (String) -> String?,
) -> ExpandedSource {
  let lines : Array[String] = []
  let missing : Array[String] = []
  lib_expand_into(source, base_dir, read, missing, lines)
  let sb = StringBuilder()
  for i in 0..<lines.length() {
    if i > 0 {
      sb.write_string("\n")
    }
    sb.write_string(lines[i])
  }
  { source: sb.to_string(), missing, }
}

///|
pub fn check_source(
  file : String,
  source : String,
) -> @validation.ValidatedLedger {
  @validation.validate_ledger(@syntax.parse_source(file, source))
}

///|
pub fn check_expanded(
  file : String,
  base_dir : String,
  source : String,
  read : (String) -> String?,
) -> @validation.ValidatedLedger {
  let expanded = expand_includes(source, base_dir, read)
  check_source(file, expanded.source)
}

///|
pub fn realize(
  ledger : @validation.ValidatedLedger,
  at~ : @ast.Date? = None,
) -> @realization.RealizedLedger {
  @realization.realize(ledger, at~)
}

///|
pub fn run_query(
  ledger : @validation.ValidatedLedger,
  statement : String,
  at~ : @ast.Date? = None,
) -> @query.QueryResult {
  @query.run_query(realize(ledger, at~), statement)
}

///|
pub fn format_source(source : String) -> String {
  @format.format_source(source)
}

///|
pub fn diagnostic_text(diagnostic : @ast.Diagnostic) -> String {
  diagnostic.loc.file +
  ":" +
  diagnostic.loc.line.to_string() +
  ": " +
  diagnostic.code +
  ": " +
  diagnostic.message
}
