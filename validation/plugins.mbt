///|
fn plugin_accounts(entry : @ast.Entry) -> Array[String] {
  match entry.directive {
    DOpen(x) => [x.account]
    DClose(x) => [x.account]
    DBalance(x) => [x.account]
    DPad(x) => [x.account, x.source_account]
    DNote(x) => [x.account]
    DDocument(x) => [x.account]
    DTransaction(x) => x.postings.map(fn(p) { p.account })
    _ => []
  }
}

///|
fn plugin_error(
  errors : Array[@ast.Diagnostic],
  code : String,
  message : String,
  loc : @ast.Loc,
) -> Unit {
  errors.push(@ast.Diagnostic::new("validation." + code, message, loc))
}

///|
fn auto_accounts(entries : Array[@ast.Entry]) -> Array[@ast.Entry] {
  let opened : Map[String, Bool] = Map([])
  for entry in entries {
    if entry.directive is DOpen(x) {
      opened.set(x.account, true)
    }
  }
  let result = entries.copy()
  for entry in sorted_entries(entries) {
    for account in plugin_accounts(entry) {
      if !opened.contains(account) {
        opened.set(account, true)
        result.push(
          @ast.Entry::new(
            entry.date,
            entry.loc,
            DOpen({ account, currencies: [], booking: None, }),
          ),
        )
      }
    }
  }
  sorted_entries(result)
}

///|
fn implicit_prices(entries : Array[@ast.Entry]) -> Array[@ast.Entry] {
  let result = entries.copy()
  let seen : Map[String, Array[@decimal.Decimal]] = Map([])
  let inventory : Map[String, @decimal.Decimal] = Map([])
  for entry in sorted_entries(entries) {
    if entry.directive is DTransaction(txn) {
      for posting in txn.postings {
        if posting.units is Some(units) {
          let mut reducing = false
          if posting.cost is Some(cost) {
            let lot = posting.account +
              "|" +
              units.currency +
              "|" +
              cost.to_string()
            let previous = inventory
              .get(lot)
              .unwrap_or(@decimal.Decimal::zero())
            reducing = !previous.is_zero() &&
              previous.is_negative() != units.number.is_negative()
            inventory.set(lot, previous.add(units.number))
          }
          let mut origin = "from_price"
          let amount = match posting.price {
            Some(PerUnit(a)) => Some(a)
            Some(Total(_)) => None
            None => {
              origin = "from_cost"
              if reducing {
                None
              } else {
                match posting.cost {
                  Some(cost) =>
                    match (cost.number_per, cost.currency) {
                      (Some(n), Some(c)) => Some(@ast.Amount::new(n, c))
                      _ => None
                    }
                  None => None
                }
              }
            }
          }
          let amount = match posting.price {
            Some(Total(a)) =>
              match a.number.div(units.number.abs()) {
                Some(n) => Some(@ast.Amount::new(n, a.currency))
                None => None
              }
            _ => amount
          }
          if amount is Some(amount) {
            let key = entry.date.to_string() +
              "|" +
              units.currency +
              "|" +
              amount.currency
            let numbers = seen.get_or_init(key, fn() { [] })
            if !numbers.any(fn(n) { n.equal(amount.number) }) {
              numbers.push(amount.number)
              let generated = @ast.Entry::new(
                entry.date,
                entry.loc,
                DPrice({ currency: units.currency, amount, }),
              )
              generated.meta.entries.push(
                ("__implicit_prices__", @ast.MetaValue::MString(origin)),
              )
              result.push(generated)
            }
          }
        }
      }
    }
  }
  sorted_entries(result)
}

///|
fn check_commodity(
  entries : Array[@ast.Entry],
  errors : Array[@ast.Diagnostic],
  exemptions : Array[(@string.Regex, @string.Regex)],
) -> Unit {
  let declared : Map[String, Bool] = Map([])
  let used : Map[String, (@ast.Loc, String)] = Map([])
  for entry in entries {
    if entry.directive is DCommodity(c) {
      declared.set(c.currency, true)
    }
    let currencies : Array[(String, String)] = []
    match entry.directive {
      DOpen(x) =>
        for c in x.currencies {
          currencies.push((c, x.account))
        }
      DBalance(x) => currencies.push((x.amount.currency, x.account))
      DPrice(x) => {
        currencies.push((x.currency, "Price Directive Context"))
        currencies.push((x.amount.currency, "Price Directive Context"))
      }
      DTransaction(txn) =>
        for p in txn.postings {
          if p.units is Some(a) {
            currencies.push((a.currency, p.account))
          }
          if p.price is Some(a) {
            currencies.push((a.amount().currency, p.account))
          }
          if p.cost is Some(c) {
            if c.currency is Some(c) {
              currencies.push((c, p.account))
            }
          }
        }
      _ => ()
    }
    for (currency, account) in currencies {
      if currency != "" &&
        !used.contains(currency) &&
        !(account != "Price Directive Context" &&
        exemptions.any(fn(pair) {
          pair.0.execute(account) is Some(_) &&
          pair.1.execute(currency) is Some(_)
        })) {
        used.set(currency, (entry.loc, account))
      }
    }
  }
  for currency in used.keys().to_array() {
    if !declared.contains(currency) {
      if used.get(currency) is Some((loc, account)) {
        plugin_error(
          errors,
          "check_commodity",
          "Missing Commodity directive for '" +
          currency +
          "' in '" +
          account +
          "'",
          loc,
        )
      }
    }
  }
}

///|
fn unique_prices(
  entries : Array[@ast.Entry],
  errors : Array[@ast.Diagnostic],
) -> Unit {
  let seen : Map[String, (@ast.Amount, @ast.Loc)] = Map([])
  let reported : Map[String, Bool] = Map([])
  for entry in entries {
    if entry.directive is DPrice(p) {
      let key = entry.date.to_string() +
        "|" +
        p.currency +
        "|" +
        p.amount.currency
      match seen.get(key) {
        Some((first, loc)) =>
          if !first.number.equal(p.amount.number) && !reported.contains(key) {
            reported.set(key, true)
            plugin_error(
              errors, "unique_prices", "Disagreeing price entries", loc,
            )
          }
        None => seen.set(key, (p.amount, entry.loc))
      }
    }
  }
}

///|
fn leafonly(
  entries : Array[@ast.Entry],
  errors : Array[@ast.Diagnostic],
) -> Unit {
  let accounts : Map[String, @ast.Loc] = Map([])
  let posted : Map[String, @ast.Loc] = Map([])
  for entry in entries {
    for name in plugin_accounts(entry) {
      accounts.set(name, entry.loc)
    }
    if entry.directive is DTransaction(t) {
      for p in t.postings {
        if !posted.contains(p.account) {
          posted.set(p.account, entry.loc)
        }
      }
    }
  }
  for account in posted.keys().to_array() {
    if accounts
      .keys()
      .to_array()
      .any(fn(name) { name.has_prefix(account + ":") }) {
      let mut loc = posted.get(account).unwrap()
      for entry in entries {
        if entry.directive is DOpen(x) {
          if x.account == account {
            loc = entry.loc
            break
          }
        }
      }
      plugin_error(
        errors,
        "leafonly",
        "Non-leaf account '" + account + "' has postings on it",
        loc,
      )
    }
  }
}

///|
fn run_plugins(
  ledger : @ast.Ledger,
  errors : Array[@ast.Diagnostic],
  warnings : Array[@ast.Diagnostic],
) -> @ast.Ledger {
  let mut entries = sorted_entries(ledger.entries)
  for plugin in ledger.plugins {
    match plugin.name {
      "beancount.plugins.auto_accounts" => entries = auto_accounts(entries)
      "beancount.plugins.implicit_prices" => entries = implicit_prices(entries)
      "beancount.plugins.check_commodity" =>
        match commodity_exemptions(plugin.config) {
          Some(exemptions) => check_commodity(entries, errors, exemptions)
          None =>
            warnings.push(
              @ast.Diagnostic::new(
                "validation.plugin",
                "未实现的插件配置 '" +
                plugin.name +
                "'；需要正则字符串字典，且正则须受 MoonBit 支持",
                plugin.loc,
              ),
            )
        }
      "beancount.plugins.unique_prices" => unique_prices(entries, errors)
      "beancount.plugins.leafonly" => leafonly(entries, errors)
      _ =>
        warnings.push(
          @ast.Diagnostic::new(
            "validation.plugin",
            "未实现的插件 '" + plugin.name + "'；仅记录，不执行",
            plugin.loc,
          ),
        )
    }
  }
  { ..ledger, entries, }
}

///|
priv struct PluginConfigParser {
  chars : Array[Char]
  mut pos : Int32
}

///|
fn PluginConfigParser::take(self : PluginConfigParser, c : Char) -> Bool {
  while self.pos < self.chars.length() &&
        (
          self.chars[self.pos] == ' ' ||
          self.chars[self.pos] == '\n' ||
          self.chars[self.pos] == '\t'
        ) {
    self.pos += 1
  }
  if self.pos < self.chars.length() && self.chars[self.pos] == c {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn PluginConfigParser::quoted(self : PluginConfigParser) -> String? {
  let quote = if self.take('\'') {
    '\''
  } else if self.take('"') {
    '"'
  } else {
    return None
  }
  let text = StringBuilder()
  while self.pos < self.chars.length() {
    let mut c = self.chars[self.pos]
    self.pos += 1
    if c == quote {
      return Some(text.to_string())
    }
    if c == '\\' {
      if self.pos >= self.chars.length() {
        return None
      }
      c = self.chars[self.pos]
      self.pos += 1
      if c != '\\' && c != '\'' && c != '"' {
        text.write_char('\\')
      }
    }
    text.write_char(c)
  }
  None
}

///|
fn commodity_exemptions(
  config : String?,
) -> Array[(@string.Regex, @string.Regex)]? {
  guard config is Some(config) else { return Some([]) }
  let parser = PluginConfigParser::{ chars: config.iter().to_array(), pos: 0, }
  if !parser.take('{') {
    return None
  }
  let result = []
  while !parser.take('}') {
    guard parser.quoted() is Some(account) else { return None }
    if !parser.take(':') {
      return None
    }
    guard parser.quoted() is Some(currency) else { return None }
    let account = @string.Regex("^(?:" + account + ")") catch {
      _ => return None
    }
    let currency = @string.Regex("^(?:" + currency + ")") catch {
      _ => return None
    }
    result.push((account, currency))
    if !parser.take(',') {
      if !parser.take('}') {
        return None
      }
      break
    }
  }
  if parser.pos < parser.chars.length() {
    if parser.chars[parser.pos:].any(fn(c) {
        c != ' ' && c != '\n' && c != '\t'
      }) {
      return None
    }
  }
  Some(result)
}
