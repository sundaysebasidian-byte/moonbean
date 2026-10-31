// Command line front end.  File system access is only used here; the library
// itself stays pure so it can be embedded in wasm and JavaScript hosts.

///|
extern "C" fn exit(code : Int32) = "exit"

///|
fn cli_view(view : StringView) -> String {
  String::from_iter(view.iter())
}

///|
fn fail(message : String) -> Unit {
  eprintln("moonbean: " + message)
  exit(1)
}

///|
fn usage() -> Unit {
  println(
    "moonbean - a Beancount-compatible plain text accounting engine\n\n" +
    "usage:\n" +
    "  moonbean check FILE...\n" +
    "  moonbean bal|bs|is FILE [--at DATE] [--convert CCY] [--json]\n" +
    "  moonbean register FILE ACCOUNT [--json]\n" +
    "  moonbean dups FILE\n" +
    "  moonbean query FILE 'BQL' [--at DATE] [--json]\n" +
    "  moonbean fmt FILE [--write]\n" +
    "  moonbean export FILE --json\n",
  )
}

///|
async fn read_text(path : String) -> String? {
  Some(@fs.read_text(path)) catch {
    _ => None
  }
}

///|
async fn expand_into(
  source : String,
  base : String,
  missing : Array[String],
  lines : Array[String],
) -> Unit {
  for view in source.split("\n") {
    let line = cli_view(view)
    match @moonbean.include_target(line) {
      Some(relative) => {
        let path = @moonbean.path_join(base, relative)
        match read_text(path) {
          Some(included) =>
            expand_into(included, @moonbean.path_dirname(path), missing, lines)
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
async fn load_ledger(file : String) -> String? {
  match read_text(file) {
    None => None
    Some(source) => {
      let lines : Array[String] = []
      let missing : Array[String] = []
      expand_into(source, @moonbean.path_dirname(file), missing, lines)
      if missing.length() > 0 {
        for path in missing {
          eprintln("moonbean: cannot read include: " + path)
        }
        return None
      }
      let sb = StringBuilder()
      for i in 0..<lines.length() {
        if i > 0 {
          sb.write_string("\n")
        }
        sb.write_string(lines[i])
      }
      Some(sb.to_string())
    }
  }
}

///|
fn print_diagnostics(diagnostics : Array[@ast.Diagnostic]) -> Unit {
  for diagnostic in diagnostics {
    eprintln(@moonbean.diagnostic_text(diagnostic))
  }
}

///|
fn print_warnings(ledger : @validation.ValidatedLedger) -> Unit {
  for diagnostic in ledger.warnings {
    eprintln("warning: " + @moonbean.diagnostic_text(diagnostic))
  }
}

///|
fn parse_date(text : String, flag : String) -> @ast.Date {
  match @ast.Date::parse(text) {
    Some(date) => date
    None => {
      fail("invalid " + flag + " date: " + text)
      @ast.Date::new(1970, 1, 1).unwrap()
    }
  }
}

///|
struct CliOptions {
  mut file : String
  mut bql : String
  mut at : @ast.Date?
  mut convert : String?
  mut json : Bool
  mut write : Bool
}

///|
fn is_option_arg(arg : String) -> Bool {
  if arg.length() <= 1 {
    return false
  }
  match arg.get_char(0) {
    Some(c) => c == '-'
    None => false
  }
}

///|
fn parse_options(command : String, args : Array[String]) -> CliOptions {
  let options = {
    file: "",
    bql: "",
    at: None,
    convert: None,
    json: false,
    write: false,
  }
  let is_query = command == "query" || command == "register"
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--at" {
      if i + 1 >= args.length() {
        fail("--at requires a date")
      }
      options.at = Some(parse_date(args[i + 1], "--at"))
      i = i + 2
    } else if arg == "--convert" {
      if i + 1 >= args.length() {
        fail("--convert requires a currency")
      }
      options.convert = Some(args[i + 1])
      i = i + 2
    } else if arg == "--json" {
      options.json = true
      i = i + 1
    } else if arg == "--write" {
      options.write = true
      i = i + 1
    } else if is_option_arg(arg) {
      fail("unknown option: " + arg)
    } else if options.file == "" {
      options.file = arg
      i = i + 1
    } else if is_query && options.bql == "" {
      options.bql = arg
      i = i + 1
    } else {
      fail("unexpected argument: " + arg)
    }
  }
  options
}

///|
async fn check_file(file : String) -> @validation.ValidatedLedger? {
  match load_ledger(file) {
    None => None
    Some(source) => Some(@moonbean.check_source(file, source))
  }
}

///|
async fn cmd_check(args : Array[String]) -> Unit {
  if args.length() == 0 {
    fail("check needs at least one file")
  }
  let mut total_errors = 0
  for file in args {
    match check_file(file) {
      None => exit(1)
      Some(ledger) => {
        print_warnings(ledger)
        print_diagnostics(ledger.errors)
        total_errors = total_errors + ledger.errors.length()
        if ledger.errors.length() == 0 {
          println(file + ": ok")
        }
      }
    }
  }
  if total_errors > 0 {
    exit(1)
  }
}

///|
async fn cmd_bal(command : String, args : Array[String]) -> Unit {
  let options = parse_options(command, args)
  if options.file == "" {
    fail("bal needs a ledger file")
  }
  match check_file(options.file) {
    None => exit(1)
    Some(ledger) => {
      print_warnings(ledger)
      if ledger.errors.length() > 0 {
        print_diagnostics(ledger.errors)
        exit(1)
      }
      let realized = @moonbean.realize(ledger, at=options.at)
      let convert = match options.convert {
        Some(currency) => Some(currency)
        None =>
          if ledger.options.operating_currencies.length() == 1 {
            Some(ledger.options.operating_currencies[0])
          } else {
            None
          }
      }
      if command == "register" {
        if options.bql == "" {
          fail("register needs an account")
        }
        let rows = @realization.register_rows(realized, options.bql)
        println(
          if options.json {
            @realization.register_to_json(rows)
          } else {
            @realization.register_to_text(rows)
          },
        )
      } else if command == "dups" {
        let duplicates = @validation.find_duplicate_transactions(ledger.entries)
        for (first, duplicate) in duplicates {
          println(
            duplicate.file +
            ":" +
            duplicate.line.to_string() +
            ": duplicate of " +
            first.file +
            ":" +
            first.line.to_string(),
          )
        }
      } else {
        let report = match command {
          "bs" => @realization.balance_sheet(realized, convert~)
          "is" => @realization.income_statement(realized, convert~)
          _ => @realization.trial_balance(realized, convert~)
        }
        println(
          if options.json {
            report.to_json()
          } else {
            report.to_text_with_options(ledger.options)
          },
        )
      }
    }
  }
}

///|
async fn cmd_query(args : Array[String]) -> Unit {
  let options = parse_options("query", args)
  if options.file == "" {
    fail("query needs a ledger file")
  }
  if options.bql == "" {
    fail("query needs a BQL statement")
  }
  match check_file(options.file) {
    None => exit(1)
    Some(ledger) => {
      print_warnings(ledger)
      if ledger.errors.length() > 0 {
        print_diagnostics(ledger.errors)
        exit(1)
      }
      let result = @moonbean.run_query(ledger, options.bql, at=options.at)
      if options.json {
        println(result.to_json())
      } else {
        println(result.to_text())
      }
      if !result.is_ok() {
        exit(1)
      }
    }
  }
}

///|
async fn cmd_fmt(args : Array[String]) -> Unit {
  let options = parse_options("fmt", args)
  if options.file == "" {
    fail("fmt needs a ledger file")
  }
  match read_text(options.file) {
    None => fail("cannot read: " + options.file)
    Some(source) => {
      let formatted = @moonbean.format_source(source)
      if options.write {
        @fs.write_text(options.file, formatted) catch {
          _ => fail("cannot write: " + options.file)
        }
      } else {
        println(cli_view(formatted.trim_end()))
      }
    }
  }
}

///|
async fn cmd_export(args : Array[String]) -> Unit {
  let options = parse_options("export", args)
  if options.file == "" {
    fail("export needs a ledger file")
  }
  match check_file(options.file) {
    None => exit(1)
    Some(ledger) => {
      print_warnings(ledger)
      if ledger.errors.length() > 0 {
        print_diagnostics(ledger.errors)
        exit(1)
      }
      println(@moonbean.export_json(options.file, ledger))
    }
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  let rest : Array[String] = []
  for i in 2..<args.length() {
    rest.push(args[i])
  }
  match args[1] {
    "check" => cmd_check(rest)
    "bal" | "bs" | "is" | "register" | "dups" => cmd_bal(args[1], rest)
    "query" => cmd_query(rest)
    "fmt" => cmd_fmt(rest)
    "export" => cmd_export(rest)
    "help" | "--help" | "-h" => usage()
    other => {
      eprintln("moonbean: unknown command: " + other)
      usage()
      exit(1)
    }
  }
}
