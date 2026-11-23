# Audit a ledger whose account roots are not English

The sample uses French account types but does not translate the directive
language. A fee of 80 USD and a rent payment of 15 USD leave 65 USD in the
bank. From the repository root, with MoonBit installed:

```sh
moon run cmd/main --target native -- check examples/financial-review/localized.bean
moon run cmd/main --target native -- bal examples/financial-review/localized.bean
moon run cmd/main --target native -- query examples/financial-review/localized.bean "SELECT account, sum(position) FROM CLEAR GROUP BY account ORDER BY account"
moon run cmd/main --target native -- query examples/financial-review/localized.bean "SELECT 2*3 FROM #"
```

The trial balance contains `Actif:Cash 65 USD`, `Depenses:Rent 15 USD` and
`Recettes:Fees -80 USD`. After CLEAR, `Capital:Earnings:Current` holds
−65 USD; the last query returns a single 6 regardless of how many postings
there are. The anonymous table has one row and zero columns. A reference
to `account` on that table is a compilation error, not the posting account.

Machine exports intentionally differ from display: `render_commas` groups
text columns only, report JSON stores exact decimal strings, and `sorted_set_json(tags)` produces an opt-in Unicode code-point order. Raw
set columns retain their existing JSON order. Fee and expense statements use the configured roots, and
currency-conversion completeness describes the period actually requested.
This example does not imply arbitrary Python plugin compatibility.
