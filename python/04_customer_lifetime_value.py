"""Customer lifetime value with the BG/NBD and Gamma-Gamma models.

BG/NBD (Fader, Hardie and Lee, 2005) models how many orders a customer places while still active and when
the customer becomes inactive, from three numbers per customer: the number of repeat orders (x), the age
of the customer at the last order (t_x) and the customer's age at the end of the data (T). The
Gamma-Gamma model (Fader and Hardie, 2013) models the value of an order. Together they give the expected
spend over the next 12 months for every customer.

The models are written here with scipy (no extra package). The script:
  1. fits BG/NBD on the first part of the data (up to 2011-06-10) and checks the predicted number of
     orders against what customers did in the next 26 weeks,
  2. refits on all data and estimates the expected 12-month spend of every customer,
  3. summarises the expected spend by RFM segment.

Run from the repository root:  python python/04_customer_lifetime_value.py
Environment variables SQL_SERVER and SQL_DATABASE override the defaults.
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyodbc
from scipy.optimize import minimize
from scipy.special import gammaln, hyp2f1

SERVER = os.getenv("SQL_SERVER", r".\SQLEXPRESS")
DATABASE = os.getenv("SQL_DATABASE", "OnlineRetailII")
CALIBRATION_END = pd.Timestamp("2011-06-10")
DATA_END = pd.Timestamp("2011-12-09")
HOLDOUT_WEEKS = (DATA_END - CALIBRATION_END).days / 7.0
HORIZON_WEEKS = 52.0

here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "results"), exist_ok=True)
os.makedirs(os.path.join(here, "figures"), exist_ok=True)

conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
    "Trusted_Connection=yes;TrustServerCertificate=yes;"
)
orders = pd.read_sql("select customer_id, order_date, order_revenue from rpt.vw_orders where customer_id is not null", conn)
seg = pd.read_sql("select customer_id, Segment from rpt.customer_segments", conn)
conn.close()
orders["order_date"] = pd.to_datetime(orders["order_date"])
orders["order_revenue"] = orders["order_revenue"].astype(float)
# one transaction per customer and day (the models count order days)
tx = orders.groupby(["customer_id", "order_date"], as_index=False)["order_revenue"].sum()


def summary(end):
    """x = repeat order days, t_x = weeks from first to last order, T = weeks from first order to end, m = average value."""
    d = tx[tx["order_date"] <= end]
    g = d.groupby("customer_id")
    s = pd.DataFrame({
        "first": g["order_date"].min(), "last": g["order_date"].max(), "n": g.size(),
        "value_sum": g["order_revenue"].sum(),
    })
    s["x"] = s["n"] - 1
    s["t_x"] = (s["last"] - s["first"]).dt.days / 7.0
    s["T"] = (end - s["first"]).dt.days / 7.0
    s["m"] = s["value_sum"] / s["n"]
    return s


# ---- BG/NBD ------------------------------------------------------------------------------
def bgnbd_nll(params, x, t_x, T):
    r, alpha, a, b = np.exp(params)
    a1 = gammaln(r + x) - gammaln(r) + r * np.log(alpha)
    a2 = gammaln(a + b) + gammaln(b + x) - gammaln(b) - gammaln(a + b + x)
    a3 = -(r + x) * np.log(alpha + T)
    a4 = np.log(a) - np.log(b + np.where(x == 0, 1, x) - 1) - (r + x) * np.log(alpha + t_x)
    ll = a1 + a2 + np.logaddexp(a3, np.where(x > 0, a4, -np.inf))
    return -ll.sum() / len(x)


def fit_bgnbd(s):
    res = minimize(bgnbd_nll, np.log([1.0, 10.0, 1.0, 3.0]), args=(s["x"].to_numpy(), s["t_x"].to_numpy(), s["T"].to_numpy()),
                   method="L-BFGS-B", bounds=[(-5, 5)] * 4)
    return np.exp(res.x), res


def expected_orders(params, x, t_x, T, t):
    """Conditional expected number of orders in the next t weeks (Fader, Hardie and Lee, 2005)."""
    r, alpha, a, b = params
    hyp = hyp2f1(r + x, b + x, a + b + x - 1, t / (alpha + T + t))
    num = (a + b + x - 1) / (a - 1) * (1 - ((alpha + T) / (alpha + T + t)) ** (r + x) * hyp)
    den = 1 + (x > 0) * (a / (b + np.where(x == 0, 1, x) - 1)) * ((alpha + T) / (alpha + t_x)) ** (r + x)
    return num / den


def p_alive(params, x, t_x, T):
    r, alpha, a, b = params
    ratio = a / (b + np.where(x == 0, 1, x) - 1) * ((alpha + T) / (alpha + t_x)) ** (r + x)
    return np.where(x == 0, 1.0, 1.0 / (1.0 + ratio))


# ---- Gamma-Gamma -------------------------------------------------------------------------
def gg_nll(params, x, m):
    p, q, v = np.exp(params)
    ll = (gammaln(p * x + q) - gammaln(p * x) - gammaln(q) + q * np.log(v)
          + (p * x - 1) * np.log(m) + p * x * np.log(x) - (p * x + q) * np.log(v + x * m))
    return -ll.sum() / len(x)


def fit_gg(s):
    rep = s[(s["n"] >= 2) & (s["m"] > 0)]
    res = minimize(gg_nll, np.log([2.0, 3.0, 20.0]), args=(rep["n"].to_numpy().astype(float), rep["m"].to_numpy()),
                   method="L-BFGS-B", bounds=[(-5, 8)] * 3)
    return np.exp(res.x)


def expected_value(params, n, m):
    p, q, v = params
    return (p * (v + n * m)) / (p * n + q - 1)


# ---- 1. validation on a hold-out period --------------------------------------------------
cal = summary(CALIBRATION_END)
bg_params, fit = fit_bgnbd(cal)
print("BG/NBD parameters (r, alpha, a, b):", bg_params.round(3), "| converged:", fit.success)
cal["pred_orders"] = expected_orders(bg_params, cal["x"].to_numpy(), cal["t_x"].to_numpy(), cal["T"].to_numpy(), HOLDOUT_WEEKS)
hold = tx[(tx["order_date"] > CALIBRATION_END) & (tx["order_date"] <= DATA_END)].groupby("customer_id").size()
cal["actual_orders"] = hold.reindex(cal.index).fillna(0)
cal["x_group"] = pd.cut(cal["x"], [-1, 0, 1, 2, 4, 9, 10_000], labels=["0", "1", "2", "3-4", "5-9", "10+"])
valid = cal.groupby("x_group", observed=True).agg(customers=("x", "size"), predicted=("pred_orders", "mean"), actual=("actual_orders", "mean")).reset_index()
tot_pred, tot_act = cal["pred_orders"].sum(), cal["actual_orders"].sum()
print(valid.round(3).to_string(index=False))
print(f"total orders in the hold-out: predicted {tot_pred:,.0f}, actual {tot_act:,.0f} ({tot_pred / tot_act - 1:+.1%})")
corr = np.corrcoef(cal["pred_orders"], cal["actual_orders"])[0, 1]
print("correlation per customer:", round(corr, 3))

# ---- 2. refit on all data and estimate the 12-month value --------------------------------
full = summary(DATA_END)
bg_full, fit_full = fit_bgnbd(full)
gg = fit_gg(full)
print("BG/NBD full:", bg_full.round(3), "| Gamma-Gamma (p, q, v):", gg.round(3))
full["expected_orders_12m"] = expected_orders(bg_full, full["x"].to_numpy(), full["t_x"].to_numpy(), full["T"].to_numpy(), HORIZON_WEEKS)
full["p_alive"] = p_alive(bg_full, full["x"].to_numpy(), full["t_x"].to_numpy(), full["T"].to_numpy())
full["expected_order_value"] = np.where(full["n"] >= 2, expected_value(gg, full["n"].to_numpy().astype(float), full["m"].to_numpy()), full["m"])
full["clv_12m"] = full["expected_orders_12m"] * full["expected_order_value"]
full = full.merge(seg, left_index=True, right_on="customer_id", how="left").set_index("customer_id")

by_seg = full.groupby("Segment").agg(
    customers=("clv_12m", "size"), mean_p_alive=("p_alive", "mean"), mean_clv_12m=("clv_12m", "mean"),
    median_clv_12m=("clv_12m", "median"), total_clv_12m=("clv_12m", "sum"),
).reset_index().sort_values("total_clv_12m", ascending=False)
by_seg["share_of_total"] = by_seg["total_clv_12m"] / by_seg["total_clv_12m"].sum()
print(by_seg.round(3).to_string(index=False))
print(f"total expected 12-month spend of existing customers: £{full['clv_12m'].sum():,.0f}")
top = full["clv_12m"].sort_values(ascending=False)
print(f"top 10% of customers hold {top.head(len(top) // 10).sum() / top.sum():.0%} of the expected value")

out = os.path.join(here, "results")
valid.round(4).to_csv(os.path.join(out, "clv_validation.csv"), index=False)
by_seg.round(4).to_csv(os.path.join(out, "clv_by_segment.csv"), index=False)
pd.DataFrame({"model": ["BG/NBD", "BG/NBD", "BG/NBD", "BG/NBD", "Gamma-Gamma", "Gamma-Gamma", "Gamma-Gamma"],
              "parameter": ["r", "alpha", "a", "b", "p", "q", "v"], "value": [*bg_full, *gg]}).round(4).to_csv(os.path.join(out, "clv_parameters.csv"), index=False)
full[["expected_orders_12m", "p_alive", "expected_order_value", "clv_12m"]].round(3).to_csv(os.path.join(out, "clv_per_customer.csv"))

# ---- figure ------------------------------------------------------------------------------
NAVY, ORANGE, GREY = "#1F3864", "#C55A11", "#7F7F7F"
fig, axes = plt.subplots(1, 3, figsize=(15, 4.6))
ax = axes[0]
pos = np.arange(len(valid))
ax.bar(pos - 0.2, valid["actual"], width=0.4, color=ORANGE, label="Actual")
ax.bar(pos + 0.2, valid["predicted"], width=0.4, color=NAVY, label="Predicted")
ax.set_xticks(pos, valid["x_group"].astype(str)); ax.set_xlabel("Repeat orders before 2011-06-10"); ax.set_ylabel("Orders in the next 26 weeks (mean)")
ax.set_title("BG/NBD check on a hold-out period", loc="left", fontsize=11); ax.legend()
ax = axes[1]
s2 = by_seg.sort_values("total_clv_12m")
ax.barh(s2["Segment"], s2["total_clv_12m"] / 1e6, color=NAVY)
for i, (v, n) in enumerate(zip(s2["total_clv_12m"] / 1e6, s2["customers"])): ax.text(v, i, f" £{v:.2f}M ({n:,} customers)", va="center", fontsize=9)
ax.set_xlim(0, s2["total_clv_12m"].max() / 1e6 * 1.6)
ax.set_xlabel("Expected spend over the next 12 months (£M)"); ax.set_title("Expected value by RFM segment", loc="left", fontsize=11)
ax = axes[2]
ax.hist(full["p_alive"], bins=30, color=NAVY)
ax.set_xlabel("Probability the customer is still active"); ax.set_ylabel("Customers")
ax.set_title("How many customers are still alive", loc="left", fontsize=11)
for a in axes:
    a.spines[["top", "right"]].set_visible(False); a.grid(alpha=0.25)
fig.tight_layout()
fig.savefig(os.path.join(here, "figures", "customer_lifetime_value.png"), dpi=150)
print("done")
