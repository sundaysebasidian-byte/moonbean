"""R12-B: find recursion depth that crashes the native CLI per construct."""
import subprocess, sys
OURS = str(__import__("pathlib").Path(__file__).resolve().parents[1] / "_build/native/debug/build/cmd/main/main.exe"); L = str(__import__("pathlib").Path(__file__).resolve().parents[1] / "tests/r9/tx.beancount")
C = {
 "parens": lambda n: "SELECT " + "(" * n + "1" + ")" * n,
 "print_parens": lambda n: "PRINT FROM " + "(" * n + "true" + ")" * n,
 "unary_minus": lambda n: "SELECT " + "-" * n + "1",
 "not": lambda n: "SELECT " + "NOT " * n + "true",
 "func": lambda n: "SELECT " + "abs(" * n + "1" + ")" * n,
 "from_subq": lambda n: "SELECT 1 FROM " + "(SELECT 1 FROM " * (n - 1) + "(SELECT 1)" + ")" * (n - 1),
 "plus_chain": lambda n: "SELECT " + "+".join(["1"] * n),
 "and_chain": lambda n: "SELECT 1 WHERE " + " AND ".join(["true"] * n),
 "in_tuple": lambda n: "SELECT 1 IN " + "(" * n + "1" + ",1)" * n,
}
def rc(q):
    try: return subprocess.run([OURS, "query", L, q, "--json"], capture_output=True, timeout=20).returncode
    except subprocess.TimeoutExpired: return "timeout"
    except OSError: return "E2BIG"
if __name__ == "__main__":
 for name, f in C.items():
    res = [(n, rc(f(n))) for n in (500, 1000, 2000, 5000, 10000, 20000, 50000)]
    print(name, res); sys.stdout.flush()
