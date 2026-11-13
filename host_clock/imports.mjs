function localDate(milliseconds) {
  const date = new Date(milliseconds);
  return date.getFullYear() * 10000 + (date.getMonth() + 1) * 100 + date.getDate();
}

// Merge this object with the application's other WebAssembly imports.
// Pass null when the host has no local calendar service, selecting UTC.
export function clockImports(provider = localDate) {
  return {
    "moonbean:clock": {
      local_date(milliseconds) {
        if (provider == null) return 0;
        const date = provider(milliseconds);
        return Number.isInteger(date) && date >= 10101 && date <= 99991231 ? date : 0;
      },
    },
  };
}
