"""Sensitivity of the revenue at risk, and a revenue forecast with an uncertainty range.

  A. How much does the headline (51% of customers, £3.30M at risk) depend on the 90-day rule?
     The churn threshold is moved from 60 to 180 days. For each threshold the script also measures,
     on earlier snapshots, how many of the customers it would have labelled churned ordered again
     within the next 90 days (the false-alarm rate of the rule).
  B. A forecast of monthly revenue for the next 6 months: last year's month multiplied by a growth
     ratio drawn from the observed year-on-year ratios (bootstrap), with a backtest of the method.

Run from the repository root:  python python/03_sensitivity_and_forecast.py
Environment variables SQL_SERVER and SQL_DATABASE override the defaults.
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyodbc

SERVER = os.getenv("SQL_SERVER", r".\SQLEXPRESS")
DATABASE = os.getenv("SQL_DATABASE", "OnlineRetailII")
SEED = 42
REF_DATE = pd.Timestamp("2011-12-09")          # last date in the data
THRESHOLDS = [60, 75, 90, 120, 150, 180]
SNAPSHOTS = [pd.Timestamp("2010-09-10"), pd.Timestamp("2010-12-09"), pd.Timestamp("2011-03-10"), pd.Timestamp("2011-06-10")]

here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "results"), exist_ok=True)
os.makedirs(os.path.join(here, "figures"), exist_ok=True)

conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
    "Trusted_Connection=yes;TrustServerCertificate=yes;"
)
orders = pd.read_sql("select customer_id, order_date, order_revenue from rpt.vw_orders", conn)
seg = pd.read_sql("select customer_id, Recency, Monetary, Segment from rpt.customer_segments", conn)
conn.close()
orders["order_date"] = pd.to_datetime(orders["order_date"])
orders["order_revenue"] = orders["order_revenue"].astype(float)
ident = orders[orders["customer_id"].notna()]

# ---- A. sensitivity of the revenue at risk -----------------------------------------------
g = ident.groupby("customer_id")
cust = pd.DataFrame({"last_order": g["order_date"].max(), "spend": g["order_revenue"].sum()})
cust["recency"] = (REF_DATE - cust["last_order"]).dt.days
print(f"{len(cust)} customers; recency check against the RFM table: max difference "
      f"{(cust['recency'].reindex(seg['customer_id']).to_numpy() - seg['Recency'].to_numpy()).__abs__().max():.0f} days")

false_alarm = {}
for t in THRESHOLDS:
    rates = []
    for snap in SNAPSHOTS:
        past = ident[ident["order_date"] <= snap]
        last = past.groupby("customer_id")["order_date"].max()
        flagged = last[(snap - last).dt.days > t].index
        future = set(ident.loc[(ident["order_date"] > snap) & (ident["order_date"] <= snap + pd.Timedelta(days=90)), "customer_id"])
        rates.append(np.mean([c in future for c in flagged]) if len(flagged) else np.nan)
    false_alarm[t] = rates

rows = []
for t in THRESHOLDS:
    c = cust[cust["recency"] > t]
    reactivation = np.nanmean(false_alarm[t])
    rows.append({
        "threshold_days": t, "churned_customers": len(c), "share_of_customers": len(c) / len(cust),
        "revenue_at_risk_gbp": c["spend"].sum(), "share_of_identified_revenue": c["spend"].sum() / cust["spend"].sum(),
        "reactivation_rate_90d": reactivation,
        "reactivation_min": np.nanmin(false_alarm[t]), "reactivation_max": np.nanmax(false_alarm[t]),
        "at_risk_after_reactivation_gbp": c["spend"].sum() * (1 - reactivation),
    })
sens = pd.DataFrame(rows)

# ---- B. forecast -------------------------------------------------------------------------
sales = orders.copy()                              # all valid sales, guests included
sales["month"] = sales["order_date"].dt.to_period("M")
monthly = sales.groupby("month")["order_revenue"].sum()
monthly = monthly[monthly.index < pd.Period("2011-12", "M")]      # December 2011 is a partial month
d = monthly.copy(); d.index = d.index.to_timestamp()
print(f"{len(monthly)} full months, {monthly.index[0]} to {monthly.index[-1]}")

ratios = pd.Series({m.month: monthly[m] / monthly[m - 12] for m in monthly.index if (m - 12) in monthly.index})
print("year-on-year ratios (2011 / 2010) by month:", ratios.round(2).to_dict())

rng = np.random.default_rng(SEED)


def forecast(target_periods, base, ratio_pool, n=10_000):
    """Revenue of target month = same month a year earlier x a ratio drawn from the observed ratios."""
    out = {}
    for m in target_periods:
        sims = base[m - 12] * rng.choice(ratio_pool, size=n)
        out[m] = (np.median(sims), *np.percentile(sims, [10, 90]), *np.percentile(sims, [2.5, 97.5]))
    return pd.DataFrame(out, index=["median", "p10", "p90", "p2_5", "p97_5"]).T


# backtest: forecast Jul to Nov 2011 from Jul to Nov 2010 using only the ratios of Jan to Jun 2011
bt_pool = np.array([monthly[pd.Period(f"2011-{m:02d}", "M")] / monthly[pd.Period(f"2010-{m:02d}", "M")] for m in range(1, 7)])
bt_months = [pd.Period(f"2011-{m:02d}", "M") for m in range(7, 12)]
bt = forecast(bt_months, monthly, bt_pool)
bt["actual"] = [monthly[m] for m in bt_months]
bt["abs_pct_error"] = (bt["median"] - bt["actual"]).abs() / bt["actual"]
bt["inside_80pct_range"] = (bt["actual"] >= bt["p10"]) & (bt["actual"] <= bt["p90"])
print(bt.round(0))
print("backtest MAPE:", round(bt["abs_pct_error"].mean(), 3), "| actuals inside the 80% range:", int(bt["inside_80pct_range"].sum()), "of", len(bt))

# forecast: December 2011 to May 2012 (the base for December is December 2010; for 2012 months, 2011)
future = [pd.Period("2011-12", "M")] + [pd.Period(f"2012-{m:02d}", "M") for m in range(1, 6)]
fc = forecast(future, monthly, ratios.to_numpy())
print(fc.round(0))

out = os.path.join(here, "results")
sens.round(4).to_csv(os.path.join(out, "sensitivity_churn_threshold.csv"), index=False)
bt.round(2).to_csv(os.path.join(out, "forecast_backtest.csv"))
fc.round(0).to_csv(os.path.join(out, "forecast_next_6_months.csv"))
pd.set_option("display.width", 250); pd.set_option("display.max_columns", 30)
print(sens.round(3).to_string(index=False))

# ---- figure ------------------------------------------------------------------------------
NAVY, ORANGE, GREY = "#1F3864", "#C55A11", "#7F7F7F"
fig, axes = plt.subplots(1, 2, figsize=(14, 4.8))
ax = axes[0]
ax.bar(sens["threshold_days"].astype(str), sens["revenue_at_risk_gbp"] / 1e6, color=NAVY, label="Past spend of customers over the threshold")
ax.bar(sens["threshold_days"].astype(str), sens["at_risk_after_reactivation_gbp"] / 1e6, color=ORANGE, width=0.45, label="After removing the share that reactivates")
for i, r in sens.iterrows():
    ax.text(i, r["revenue_at_risk_gbp"] / 1e6 + 0.04, f"{int(r['churned_customers']):,} customers", ha="center", fontsize=8)
ax.set_xlabel("Churn threshold (days without an order)"); ax.set_ylabel("Revenue at risk (£M)")
ax.set_title("Revenue at risk by churn threshold", loc="left", fontsize=11); ax.legend(fontsize=8)
ax = axes[1]
hist = d[d.index >= "2010-01-01"]
ax.plot(hist.index, hist.values / 1e3, color=NAVY, lw=2, label="Actual (full months)")
fx = [p.to_timestamp() for p in fc.index]
ax.plot(fx, fc["median"] / 1e3, color=ORANGE, lw=2, label="Forecast (median)")
ax.fill_between(fx, fc["p10"] / 1e3, fc["p90"] / 1e3, color=ORANGE, alpha=0.25, label="80% range")
ax.fill_between(fx, fc["p2_5"] / 1e3, fc["p97_5"] / 1e3, color=ORANGE, alpha=0.12, label="95% range")
ax.set_ylabel("Revenue (£ thousand)"); ax.set_title("Monthly revenue and the next 6 months", loc="left", fontsize=11); ax.legend(fontsize=8)
for a in axes:
    a.spines[["top", "right"]].set_visible(False); a.grid(alpha=0.25)
fig.tight_layout()
fig.savefig(os.path.join(here, "figures", "sensitivity_and_forecast.png"), dpi=150)
print("done")
