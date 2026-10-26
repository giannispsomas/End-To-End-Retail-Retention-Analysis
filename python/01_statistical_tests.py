"""Statistical tests for the retention findings: are the differences real?

The case study states three results from the data as they are. This script tests them:

  A. Repeat customers spend far more than one-time customers
     (Mann-Whitney U test, difference in median spend with a bootstrap interval, Cliff's delta).
  B. The median time to a second order is 57 days and 31% of repeat customers come back within 30 days
     (bootstrap intervals).
  C. Customers return more in autumn (October and November) than in winter (January and February)
     (share of customer-months with an order, bootstrap interval resampling customers, chi-square test).

Run from the repository root:  python python/01_statistical_tests.py
Environment variables SQL_SERVER and SQL_DATABASE override the defaults.
Writes results to python/results/ (CSV) and python/figures/ (PNG).
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyodbc
from scipy import stats

SERVER = os.getenv("SQL_SERVER", r".\SQLEXPRESS")
DATABASE = os.getenv("SQL_DATABASE", "OnlineRetailII")
N_BOOT = 5_000
SEED = 42
here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "results"), exist_ok=True)
os.makedirs(os.path.join(here, "figures"), exist_ok=True)

conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
    "Trusted_Connection=yes;TrustServerCertificate=yes;"
)
cust = pd.read_sql(
    """
    select customer_id, is_censored, order_count, total_revenue, first_order_date,
           second_order_date, days_to_second_order, is_repeat_customer
    from rpt.vw_customer_summary
    where customer_id is not null
    """, conn)
orders = pd.read_sql("select customer_id, order_date from rpt.vw_orders where customer_id is not null", conn)
conn.close()

cust["total_revenue"] = cust["total_revenue"].astype(float)
orders["order_date"] = pd.to_datetime(orders["order_date"])
rng = np.random.default_rng(SEED)
print(f"{len(cust)} identified customers, {int(cust['is_repeat_customer'].sum())} repeat")


def boot_ci(stat, a, n=N_BOOT, b=None):
    """95% bootstrap interval of stat(sample) for one sample (a) or the difference stat(a)-stat(b)."""
    out = np.empty(n)
    for i in range(n):
        sa = a[rng.integers(0, len(a), len(a))]
        out[i] = stat(sa) if b is None else stat(sa) - stat(b[rng.integers(0, len(b), len(b))])
    return np.percentile(out, [2.5, 97.5])


def cliffs_delta(x, y):
    u = stats.mannwhitneyu(x, y, alternative="two-sided").statistic
    return 2 * u / (len(x) * len(y)) - 1


# ---- A. repeat vs one-time spend ---------------------------------------------------------
rows = []
for label, d in [("all identified customers", cust),
                 ("customers with 90+ days of history (not censored)", cust[cust["is_censored"] == 0])]:
    rep = d.loc[d["is_repeat_customer"] == 1, "total_revenue"].to_numpy()
    one = d.loc[d["is_repeat_customer"] == 0, "total_revenue"].to_numpy()
    u = stats.mannwhitneyu(rep, one, alternative="two-sided")
    med_ci = boot_ci(np.median, rep, b=one)
    rows.append({
        "group": label, "repeat_customers": len(rep), "one_time_customers": len(one),
        "median_repeat": np.median(rep), "median_one_time": np.median(one),
        "median_difference": np.median(rep) - np.median(one),
        "diff_low": med_ci[0], "diff_high": med_ci[1],
        "mean_repeat": rep.mean(), "mean_one_time": one.mean(),
        "cliffs_delta": cliffs_delta(rep, one), "mannwhitney_p": u.pvalue,
    })
test_a = pd.DataFrame(rows)

# ---- B. time to second order -------------------------------------------------------------
gaps = cust.loc[cust["is_repeat_customer"] == 1, "days_to_second_order"].dropna().to_numpy().astype(float)
med = np.median(gaps); med_ci = boot_ci(np.median, gaps)
share30 = (gaps <= 30).mean(); share_ci = boot_ci(lambda x: (x <= 30).mean(), gaps)
test_b = pd.DataFrame([
    {"metric": "median days to second order", "value": med, "low": med_ci[0], "high": med_ci[1]},
    {"metric": "share of repeat customers returning within 30 days", "value": share30, "low": share_ci[0], "high": share_ci[1]},
    {"metric": "repeat customers in the sample", "value": len(gaps), "low": np.nan, "high": np.nan},
])

# ---- C. seasonality of returns -----------------------------------------------------------
# a customer-month is one customer in one calendar month after their first-order month.
orders["ym"] = orders["order_date"].dt.year * 12 + orders["order_date"].dt.month - 1
first = orders.groupby("customer_id")["ym"].min()
last_ym = orders["ym"].max() - 1                      # December 2011 is partial, so it is left out
active = orders.groupby("customer_id")["ym"].agg(lambda s: set(s))
ids = first.index.to_numpy()
obs_customer, obs_month, obs_ordered = [], [], []
for k, cid in enumerate(ids):
    f = first[cid]
    for m in range(f + 1, last_ym + 1):
        obs_customer.append(k); obs_month.append(m % 12 + 1); obs_ordered.append(int(m in active[cid]))
obs = pd.DataFrame({"c": obs_customer, "month": obs_month, "ordered": obs_ordered})
obs["season"] = np.select([obs["month"].isin([10, 11]), obs["month"].isin([1, 2])], ["autumn (Oct, Nov)", "winter (Jan, Feb)"], "other")
by_month = obs.groupby("month")["ordered"].agg(["mean", "size"]).reset_index().rename(columns={"mean": "share_ordering", "size": "customer_months"})

sub = obs[obs["season"] != "other"]
table = pd.crosstab(sub["season"], sub["ordered"])
chi2, p_chi, _, _ = stats.chi2_contingency(table)
aut = sub.loc[sub["season"].str.startswith("autumn"), "ordered"].mean()
win = sub.loc[sub["season"].str.startswith("winter"), "ordered"].mean()

# bootstrap by customer: the customer-months of one customer are not independent
cust_ids = obs["c"].to_numpy()
order_idx = np.argsort(cust_ids, kind="stable")
cs = obs.iloc[order_idx].reset_index(drop=True)
starts = np.r_[0, np.flatnonzero(np.diff(cs["c"].to_numpy())) + 1]
ends = np.r_[starts[1:], len(cs)]
is_aut = cs["season"].str.startswith("autumn").to_numpy(); is_win = cs["season"].str.startswith("winter").to_numpy()
ordered = cs["ordered"].to_numpy()
n_aut = np.array([is_aut[s:e].sum() for s, e in zip(starts, ends)]); y_aut = np.array([(ordered[s:e] * is_aut[s:e]).sum() for s, e in zip(starts, ends)])
n_win = np.array([is_win[s:e].sum() for s, e in zip(starts, ends)]); y_win = np.array([(ordered[s:e] * is_win[s:e]).sum() for s, e in zip(starts, ends)])
diffs = np.empty(N_BOOT)
for i in range(N_BOOT):
    j = rng.integers(0, len(starts), len(starts))
    diffs[i] = y_aut[j].sum() / n_aut[j].sum() - y_win[j].sum() / n_win[j].sum()
d_ci = np.percentile(diffs, [2.5, 97.5])
test_c = pd.DataFrame([{
    "autumn_share_ordering": aut, "winter_share_ordering": win, "difference": aut - win,
    "diff_low": d_ci[0], "diff_high": d_ci[1], "chi2": chi2, "chi2_p": p_chi,
    "customer_months_autumn": int(n_aut.sum()), "customer_months_winter": int(n_win.sum()),
}])

# ---- save and print ----------------------------------------------------------------------
out = os.path.join(here, "results")
test_a.to_csv(os.path.join(out, "stats_repeat_vs_one_time.csv"), index=False)
test_b.to_csv(os.path.join(out, "stats_time_to_second_order.csv"), index=False)
test_c.to_csv(os.path.join(out, "stats_seasonality.csv"), index=False)
by_month.to_csv(os.path.join(out, "stats_return_share_by_month.csv"), index=False)
pd.set_option("display.width", 220); pd.set_option("display.max_columns", 30)
print(test_a.round(3).T, "\n"); print(test_b.round(3), "\n"); print(test_c.round(4).T, "\n"); print(by_month.round(3))

# ---- figure ------------------------------------------------------------------------------
NAVY, ORANGE, GREY = "#1F3864", "#C55A11", "#7F7F7F"
fig, axes = plt.subplots(1, 3, figsize=(15, 4.6))
ax = axes[0]
bins = np.logspace(1, 5.5, 40)
ax.hist(cust.loc[cust["is_repeat_customer"] == 0, "total_revenue"].clip(lower=10), bins=bins, color=GREY, alpha=0.8, label="One-time")
ax.hist(cust.loc[cust["is_repeat_customer"] == 1, "total_revenue"].clip(lower=10), bins=bins, color=NAVY, alpha=0.8, label="Repeat")
ax.set_xscale("log"); ax.set_xlabel("Total spend per customer (£, log scale)"); ax.set_ylabel("Customers")
ax.set_title("Spend: repeat vs one-time customers", loc="left", fontsize=11); ax.legend()
ax = axes[1]
ax.hist(gaps, bins=np.arange(0, 400, 10), color=NAVY)
ax.axvline(med, color=ORANGE, lw=2, label=f"Median {med:.0f} days ({med_ci[0]:.0f} to {med_ci[1]:.0f})")
ax.axvline(30, color=GREY, ls="--", lw=1.5, label=f"30 days: {share30:.0%} return by then")
ax.set_xlabel("Days to second order"); ax.set_ylabel("Repeat customers")
ax.set_title("Time to second order", loc="left", fontsize=11); ax.legend(fontsize=8)
ax = axes[2]
cols = [ORANGE if m in (10, 11) else NAVY if m in (1, 2) else "#BFBFBF" for m in by_month["month"]]
ax.bar(by_month["month"], by_month["share_ordering"] * 100, color=cols)
ax.set_xticks(range(1, 13)); ax.set_xlabel("Calendar month"); ax.set_ylabel("Customers ordering (%)")
ax.set_title("Share of returning-age customers ordering, by month", loc="left", fontsize=11)
for a in axes:
    a.spines[["top", "right"]].set_visible(False); a.grid(alpha=0.25)
fig.tight_layout()
fig.savefig(os.path.join(here, "figures", "statistical_tests.png"), dpi=150)
print("done")
