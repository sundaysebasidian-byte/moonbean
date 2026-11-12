///|
fn ledger_quote(text : String) -> String {
  "\"" +
  text.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"") +
  "\""
}

///|
fn ledger_metadata(meta : @ast.Meta, indent : String) -> String {
  let out = StringBuilder()
  for (key, value) in meta.entries {
    if key.has_prefix("__") || ["filename", "lineno"].contains(key) {
      continue
    }
    out.write_string(
      indent +
      key +
      ": " +
      (match value {
        MString(s) => ledger_quote(s)
        MNumber(n) => python_decimal(n)
        other => other.to_string()
      }) +
      "\n",
    )
  }
  out.to_string()
}

///|
fn ledger_tags(tags : Array[String], links : Array[String]) -> String {
  let tags = tags.copy()
  let links = links.copy()
  tags.sort()
  links.sort()
  tags.map(fn(s) { " #" + s }).join("") + links.map(fn(s) { " ^" + s }).join("")
}

///|
fn ledger_entry(entry : @ast.Entry) -> String {
  let out = StringBuilder()
  out.write_string(entry.date.to_string() + " ")
  match entry.directive {
    DOpen(o) =>
      out.write_string(
        "open " +
        (if o.currencies.is_empty() && o.booking is None {
          o.account
        } else {
          pad_right(o.account, 47) +
          " " +
          o.currencies.join(",") +
          o.booking
          .map(fn(b) {
            " " +
            ledger_quote(
              if [
                  "STRICT", "STRICT_WITH_SIZE", "FIFO", "LIFO", "HIFO", "NONE", "AVERAGE",
                ].contains(b) {
                b
              } else {
                "STRICT"
              },
            )
          })
          .unwrap_or("")
        }),
      )
    DClose(c) => out.write_string("close " + c.account)
    DCommodity(c) => out.write_string("commodity " + c.currency)
    DPad(p) => out.write_string("pad " + p.account + " " + p.source_account)
    DBalance(b) =>
      out.write_string(
        "balance " +
        pad_right(b.account, 47) +
        " " +
        b.amount.number.to_string() +
        b.tolerance.map(fn(n) { " ~ " + python_decimal(n) }).unwrap_or("") +
        " " +
        b.amount.currency +
        entry.balance_discrepancy
        .map(fn(a) { "   ; Diff: " + a.number.to_string() + " " + a.currency })
        .unwrap_or(""),
      )
    DPrice(p) =>
      out.write_string(
        "price " +
        pad_right(p.currency, 22) +
        " " +
        pad_left(p.amount.number.to_string(), 18) +
        " " +
        p.amount.currency,
      )
    DNote(n) =>
      out.write_string(
        "note " +
        n.account +
        " " +
        ledger_quote(n.comment) +
        ledger_tags(n.tags, n.links),
      )
    DDocument(d) =>
      out.write_string(
        "document " +
        d.account +
        " " +
        ledger_quote(document_filename(entry, d)) +
        ledger_tags(d.tags, d.links),
      )
    DEvent(e) =>
      out.write_string(
        "event " +
        ledger_quote(e.event_type) +
        " " +
        ledger_quote(e.description),
      )
    DQuery(q) =>
      out.write_string(
        "query " + ledger_quote(q.name) + " " + ledger_quote(q.query),
      )
    DCustom(c) =>
      out.write_string(
        "custom " +
        ledger_quote(c.custom_type) +
        c.values
        .map(fn(v) {
          " " +
          (match v {
            CString(s) => ledger_quote(s)
            CNumber(n) => python_decimal(n)
            CAmount(a) => python_decimal(a.number) + " " + a.currency
            other => other.to_string()
          })
        })
        .join(""),
      )
    DTransaction(t) => {
      out.write_string(
        t.flag +
        " " +
        t.payee
        .map(fn(s) { if s == "" { "" } else { ledger_quote(s) + " " } })
        .unwrap_or("") +
        (if t.narration == "" { "" } else { ledger_quote(t.narration) }) +
        ledger_tags(t.tags, t.links),
      )
      out.write_string("\n" + ledger_metadata(entry.meta, "  "))
      let postings = booked_postings(t.postings)
      let mut account_width = 0
      let mut number_width = 0
      for p in postings {
        account_width = account_width.max(
          p.account.iter().count() + p.flag.map(fn(_) { 2 }).unwrap_or(0),
        )
        if p.units is Some(a) {
          number_width = number_width.max(a.number.to_string().length())
        }
      }
      for p in postings {
        let account = p.flag.map(fn(f) { f + " " }).unwrap_or("") + p.account
        out.write_string(
          "  " +
          account +
          " ".repeat(account_width - account.iter().count()) +
          "  ",
        )
        if p.units is Some(a) {
          out.write_string(
            pad_left(a.number.to_string(), number_width) + " " + a.currency,
          )
          if posting_cost(p, a) is Some(c) {
            out.write_string(
              " {" +
              c.number.to_string() +
              " " +
              c.currency +
              c.date.map(fn(d) { ", " + d.to_string() }).unwrap_or("") +
              c.label.map(fn(s) { ", " + ledger_quote(s) }).unwrap_or("") +
              "}",
            )
          }
        }
        if posting_price(p) is QAmount(a) {
          out.write_string(" @ " + a.number.to_string() + " " + a.currency)
        }
        out.write_string("\n" + ledger_metadata(p.meta, "    "))
      }
      return out.to_string()
    }
  }
  out.write_string("\n" + ledger_metadata(entry.meta, "  "))
  out.to_string()
}

///|
fn pad_left(text : String, width : Int32) -> String {
  " ".repeat((width - text.length()).max(0)) + text
}

///|
fn run_print(
  realized : @realization.RealizedLedger,
  filter : Cond,
  period : QuerySource,
  diagnostics : Array[@ast.Diagnostic],
) -> QueryResult {
  let realized = {
    ..realized,
    entries: print_recovered_entries(realized.entries, diagnostics),
  }
  let ctx = QueryContext::new(realized, SrcDirectives("entries"))
  let selected : Array[@ast.Entry] = []
  for row in directive_rows(realized, "entries") {
    if cond_holds(ctx, filter, row) && row_entry(row) is Some(e) {
      selected.push(e)
    }
  }
  let entries = print_period(realized, selected, period)
  let out = StringBuilder()
  let rows : Array[Array[QueryValue]] = []
  let mut previous = ""
  for e in entries {
    let kind = directive_type(e)
    if (previous != "" && previous != kind) ||
      !["open", "close", "balance", "note", "event", "price"].contains(kind) {
      out.write_char('\n')
    }
    out.write_string(ledger_entry(e))
    rows.push([directive_value(e)])
    previous = kind
  }
  {
    columns: ["ROW(*)"],
    rows,
    error: ctx.error,
    kind: DirectiveText(out.to_string()),
  }
}

///|
fn print_period(
  realized : @realization.RealizedLedger,
  entries : Array[@ast.Entry],
  period : QuerySource,
) -> Array[@ast.Entry] {
  match period {
    SrcFrom(_, start, end, close_all, clear) => {
      let initial = match start {
        Some(start) => print_period(realized, entries, SrcOpen(start, end))
        None =>
          match end {
            Some(end) => print_period(realized, entries, SrcClose(end))
            None => entries
          }
      }
      let closed = if close_all && initial.last() is Some(last) {
        print_close_at(
          realized,
          initial,
          last.date,
          "account_current_conversions",
          "Conversions:Current",
        )
      } else {
        initial
      }
      if clear {
        let date = match end {
          Some(end) => ordinal_date(ordinal(end) - 1)
          None => closed.last().map(fn(e) { QDate(e.date) }).unwrap_or(QNull)
        }
        match date {
          QDate(date) => print_clear(realized, closed, date)
          _ => closed
        }
      } else {
        closed
      }
    }
    SrcClose(end) =>
      print_close(
        realized, entries, end, "account_current_conversions", "Conversions:Current",
      )
    SrcOpen(start, end) => {
      let result : Array[@ast.Entry] = []
      let active : Map[String, @ast.Entry] = Map([])
      let prices : Map[String, @ast.Entry] = Map([])
      for e in entries {
        if e.date.less_than(start) {
          match e.directive {
            DOpen(o) =>
              if !active.contains(o.account) {
                active.set(o.account, e)
              }
            DClose(c) => active.remove(c.account) |> ignore
            DPrice(p) => prices.set(p.currency + ":" + p.amount.currency, e)
            _ => ()
          }
        }
      }
      for e in entries {
        if e.date.less_than(start) &&
          e.directive is DOpen(o) &&
          active.get(o.account) is Some(first) &&
          first.loc.file == e.loc.file &&
          first.loc.line == e.loc.line {
          result.push(e)
        }
      }
      for e in entries {
        if e.date.less_than(start) &&
          e.directive is DPrice(p) &&
          prices.get(p.currency + ":" + p.amount.currency) is Some(last) &&
          e.loc.file == last.loc.file &&
          e.loc.line == last.loc.line {
          result.push(e)
        }
      }
      let before = print_close(
        realized, entries, start, "account_previous_conversions", "Conversions:Previous",
      )
      let filtered = {
        ..realized,
        entries: before + entries.filter(fn(e) { !e.date.less_than(start) }),
      }
      let summaries = opening_rows(filtered, start, end)
      let mut i = 0
      while i + 1 < summaries.length() && summaries[i].flag == "S" {
        let a = summaries[i]
        let t = @ast.Transaction::new("S", None, a.narration, [], [])
        while i + 1 < summaries.length() &&
              summaries[i].flag == "S" &&
              summaries[i].account == a.account {
          for row in [summaries[i], summaries[i + 1]] {
            let p = @ast.Posting::new(row.account)
            p.units = Some(row.units)
            p.cost = row.cost.map(fn(c) {
              @ast.CostSpec::new_per(c.number, c.currency, c.date, c.label)
            })
            t.postings.push(p)
          }
          i = i + 2
        }
        result.push(
          @ast.Entry::new(
            a.date,
            @ast.Loc::new("<summarize>", 0),
            DTransaction(t),
          ),
        )
      }
      for e in entries {
        if !e.date.less_than(start) &&
          end.map(fn(d) { e.date.less_than(d) }).unwrap_or(true) {
          result.push(e)
        }
      }
      result
      .mut_view()
      .stable_sort_by(fn(a, b) {
        let date = a.date.compare(b.date)
        if date != 0 {
          return date
        }
        match (a.directive, b.directive) {
          (DTransaction(x), DTransaction(y)) =>
            python_text_compare(x.narration, y.narration)
          (DTransaction(_), DPrice(_)) => -1
          (DPrice(_), DTransaction(_)) => 1
          _ => 0
        }
      })
      match end {
        Some(end) =>
          print_close(
            realized, result, end, "account_current_conversions", "Conversions:Current",
          )
        None => result
      }
    }
    _ => entries
  }
}

///|
fn print_close(
  realized : @realization.RealizedLedger,
  entries : Array[@ast.Entry],
  end : @ast.Date,
  option : String,
  suffix : String,
) -> Array[@ast.Entry] {
  let entries = entries.filter(fn(e) { e.date.less_than(end) })
  match ordinal_date(ordinal(end) - 1) {
    QDate(date) => print_close_at(realized, entries, date, option, suffix)
    _ => entries
  }
}

///|
fn print_close_at(
  realized : @realization.RealizedLedger,
  entries : Array[@ast.Entry],
  date : @ast.Date,
  option : String,
  suffix : String,
) -> Array[@ast.Entry] {
  let result = entries.copy()
  let inventory = @booking.Inventory::new()
  for row in posting_rows({ ..realized, entries: result, }, false) {
    inventory.add(row.position)
  }
  let residual = @booking.Inventory::new()
  for p in inventory.positions {
    residual.add_amount(
      match p.cost {
        Some(c) => @ast.Amount::new(p.units.number.mul(c.number), c.currency)
        None => p.units
      },
    )
  }
  if residual.is_empty() {
    return result
  }
  let t = @ast.Transaction::new(
    "C",
    None,
    "Conversion for " + inventory_repr(inventory),
    [],
    [],
  )
  for p in residual.positions {
    let posting = @ast.Posting::new(
      realized.options.equity_account(option, suffix),
    )
    posting.units = Some(
      @ast.Amount::new(p.units.number.neg(), p.units.currency),
    )
    posting.price = Some(
      PerUnit(@ast.Amount::new(@decimal.Decimal::zero(), "NOTHING")),
    )
    t.postings.push(posting)
  }
  result.push(
    @ast.Entry::new(date, @ast.Loc::new("<conversions>", 0), DTransaction(t)),
  )
  result
}

///|
fn print_recovered_entries(
  entries : Array[@ast.Entry],
  diagnostics : Array[@ast.Diagnostic],
) -> Array[@ast.Entry] {
  let result : Array[@ast.Entry] = []
  for e in entries {
    if e.directive is DTransaction(t) {
      let same_location = fn(a : @ast.Loc, b : @ast.Loc) {
        a.file == b.file && a.line == b.line
      }
      if t.postings.filter(fn(p) { p.units is None }).length() > 1 &&
        diagnostics.any(fn(d) {
          d.code == "validation.missing" &&
          (
            same_location(d.loc, e.loc) ||
            t.postings.any(fn(p) { same_location(d.loc, p.loc) })
          )
        }) {
        continue
      }
      if diagnostics.any(fn(d) {
          d.code == "validation.booking" && same_location(d.loc, e.loc)
        }) {
        let recovered = @ast.Transaction::new(
          t.flag,
          t.payee,
          t.narration,
          t.tags,
          t.links,
        )
        result.push({ ..e, directive: DTransaction(recovered), })
        continue
      }
    }
    result.push(e)
  }
  result
}

///|
fn print_clear(
  realized : @realization.RealizedLedger,
  entries : Array[@ast.Entry],
  date : @ast.Date,
) -> Array[@ast.Entry] {
  let balances : Map[String, @booking.Inventory] = Map([])
  for row in posting_rows({ ..realized, entries, }, false) {
    if ["Income", "Expenses"].contains(@ast.account_root(row.account)) {
      balances
      .get_or_init(row.account, fn() { @booking.Inventory::new() })
      .add(row.position)
    }
  }
  let result = entries.copy()
  let accounts = balances.keys().to_array()
  accounts.sort_by(python_text_compare)
  for account in accounts {
    let inventory = balances.get(account).unwrap()
    if inventory.is_empty() {
      continue
    }
    let t = @ast.Transaction::new(
      "T",
      None,
      "Transfer balance for '" + account + "' (Transfer balance)",
      [],
      [],
    )
    for position in inventory.positions {
      let p = @ast.Posting::new(account)
      p.units = Some(
        @ast.Amount::new(
          position.units.number.neg().round_to_significant(28),
          position.units.currency,
        ),
      )
      p.cost = position.cost.map(fn(c) {
        @ast.CostSpec::new_per(c.number, c.currency, c.date, c.label)
      })
      let q = @ast.Posting::new(
        realized.options.equity_account(
          "account_current_earnings", "Earnings:Current",
        ),
      )
      q.units = Some(
        match position.cost {
          Some(c) =>
            @ast.Amount::new(
              position.units.number.mul(c.number).round_to_significant(28),
              c.currency,
            )
          None => position.units
        },
      )
      t.postings.append([p, q])
    }
    result.push(
      @ast.Entry::new(
        date,
        @ast.Loc::new("<transfer_balances>", 0),
        DTransaction(t),
      ),
    )
  }
  result
}
