"""A forward-looking churn model, evaluated on a later period.

The model in churn_regr.ipynb labels a customer as churned from the same snapshot that its features
come from, so it describes who looks lapsed today and is not a forecast. This script builds the
forward-looking version:

  - Snapshot date: the features use only orders up to the snapshot.
  - Label: the customer places no order in the 90 days after the snapshot.
  - Time-based split: the models are trained at the snapshot of 2011-06-10 (outcome known by 2011-09-08)
    and tested at the snapshot of 2011-09-10 (outcome known by the end of the data, 2011-12-09).
    The test period has no overlap with anything the models saw.

Models: logistic regression on frequency and monetary value (the original), logistic regression on
all features, random forest and gradient boosting, plus two simple rules as baselines.
Evaluation: ROC-AUC, average precision, Brier score, calibration, and precision and recall when the
highest-risk 20% of customers are contacted.

Run from the repository root:  python python/02_churn_model_evaluation.py
Environment variables SQL_SERVER and SQL_DATABASE override the defaults.
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyodbc
from sklearn.calibration import calibration_curve
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score, roc_curve
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

SERVER = os.getenv("SQL_SERVER", r".\SQLEXPRESS")
DATABASE = os.getenv("SQL_DATABASE", "OnlineRetailII")
SEED = 42
HORIZON = 90
TRAIN_SNAPSHOT = pd.Timestamp("2011-06-10")
TEST_SNAPSHOT = pd.Timestamp("2011-09-10")
DATA_END = pd.Timestamp("2011-12-09")
TOP_SHARE = 0.20

here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "results"), exist_ok=True)
os.makedirs(os.path.join(here, "figures"), exist_ok=True)

conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
    "Trusted_Connection=yes;TrustServerCertificate=yes;"
)
orders = pd.read_sql("select customer_id, order_date, order_revenue from rpt.vw_orders where customer_id is not null", conn)
conn.close()
orders["order_date"] = pd.to_datetime(orders["order_date"])
orders["order_revenue"] = orders["order_revenue"].astype(float)


def build(snapshot):
    """One row per customer active before the snapshot: features from the past, label from the next 90 days."""
    past = orders[orders["order_date"] <= snapshot]
    future = orders[(orders["order_date"] > snapshot) & (orders["order_date"] <= snapshot + pd.Timedelta(days=HORIZON))]
    g = past.groupby("customer_id")
    f = pd.DataFrame({
        "recency": (snapshot - g["order_date"].max()).dt.days,
        "frequency": g.size(),
        "monetary": g["order_revenue"].sum(),
        "tenure": (snapshot - g["order_date"].min()).dt.days,
        "orders_last_90d": past[past["order_date"] > snapshot - pd.Timedelta(days=90)].groupby("customer_id").size(),
    })
    f["orders_last_90d"] = f["orders_last_90d"].fillna(0)
    f["avg_gap"] = np.where(f["frequency"] > 1, f["tenure"] / (f["frequency"] - 1).clip(lower=1), f["tenure"] + 1)
    f["monetary_log"] = np.log1p(f["monetary"].clip(lower=0))
    f["churned"] = (~f.index.isin(future["customer_id"].unique())).astype(int)
    return f


train, test = build(TRAIN_SNAPSHOT), build(TEST_SNAPSHOT)
assert TEST_SNAPSHOT + pd.Timedelta(days=HORIZON) >= DATA_END - pd.Timedelta(days=1)
print(f"train: {len(train)} customers, churn rate {train['churned'].mean():.3f}")
print(f"test:  {len(test)} customers, churn rate {test['churned'].mean():.3f}")

FEATURE_SETS = {
    "frequency + monetary": ["frequency", "monetary_log"],
    "all features": ["recency", "frequency", "monetary_log", "tenure", "orders_last_90d", "avg_gap"],
}
models = {
    "Logistic regression (frequency + monetary)": (make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000)), FEATURE_SETS["frequency + monetary"]),
    "Logistic regression (all features)": (make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000)), FEATURE_SETS["all features"]),
    "Random forest": (RandomForestClassifier(n_estimators=300, min_samples_leaf=10, random_state=SEED, n_jobs=1), FEATURE_SETS["all features"]),
    "Gradient boosting": (GradientBoostingClassifier(n_estimators=150, max_depth=2, learning_rate=0.05, random_state=SEED), FEATURE_SETS["all features"]),
}

y_tr, y_te = train["churned"].to_numpy(), test["churned"].to_numpy()
skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)
rows, scores = [], {}
for name, (model, cols) in models.items():
    cv_auc = cross_val_score(model, train[cols], y_tr, cv=skf, scoring="roc_auc")
    model.fit(train[cols], y_tr)
    p = model.predict_proba(test[cols])[:, 1]
    scores[name] = p
    rows.append((name, cv_auc, p))

# simple rules as baselines (higher score = more likely churned)
scores["Rule: days since last order"] = test["recency"].to_numpy().astype(float)
scores["Rule: fewer orders"] = -test["frequency"].to_numpy().astype(float)


def top_share_metrics(score, y, share=TOP_SHARE):
    k = int(round(len(y) * share))
    idx = np.argsort(-score)[:k]
    tp = y[idx].sum()
    return tp / k, tp / y.sum(), (tp / k) / y.mean()


table = []
for name, p in scores.items():
    prec, rec, lift = top_share_metrics(p, y_te)
    cv_mean = next((c.mean() for n, c, _ in rows if n == name), np.nan)
    cv_sd = next((c.std() for n, c, _ in rows if n == name), np.nan)
    is_prob = name in models
    table.append({
        "model": name, "cv_auc_train_period": cv_mean, "cv_auc_sd": cv_sd,
        "test_auc": roc_auc_score(y_te, p), "average_precision": average_precision_score(y_te, p),
        "brier_score": brier_score_loss(y_te, p) if is_prob else np.nan,
        f"precision_top_{int(TOP_SHARE * 100)}pct": prec, f"recall_top_{int(TOP_SHARE * 100)}pct": rec, "lift_top": lift,
    })
res = pd.DataFrame(table).sort_values("test_auc", ascending=False)
res.attrs["base_rate"] = y_te.mean()

# bootstrap interval for the AUC of the best and the original model on the test set
rng = np.random.default_rng(SEED)
ci_rows = []
for name in ["Logistic regression (frequency + monetary)", res.iloc[0]["model"]]:
    p = scores[name]; aucs = []
    for _ in range(1000):
        i = rng.integers(0, len(y_te), len(y_te))
        if y_te[i].min() != y_te[i].max(): aucs.append(roc_auc_score(y_te[i], p[i]))
    ci_rows.append({"model": name, "auc_low": np.percentile(aucs, 2.5), "auc_high": np.percentile(aucs, 97.5)})
ci = pd.DataFrame(ci_rows).drop_duplicates("model")

# importances from the gradient boosting model
gb, gb_cols = models["Gradient boosting"]
imp = pd.DataFrame({"feature": gb_cols, "importance": gb.feature_importances_}).sort_values("importance", ascending=False)

out = os.path.join(here, "results")
res.round(4).to_csv(os.path.join(out, "churn_eval_models.csv"), index=False)
ci.round(4).to_csv(os.path.join(out, "churn_eval_auc_intervals.csv"), index=False)
imp.round(4).to_csv(os.path.join(out, "churn_eval_importance.csv"), index=False)
pd.set_option("display.width", 250); pd.set_option("display.max_columns", 30)
print(res.round(3).to_string(index=False), "\n"); print(ci.round(3).to_string(index=False), "\n"); print(imp.round(3).to_string(index=False))
print("test base churn rate:", round(y_te.mean(), 3))

# ---- figure ------------------------------------------------------------------------------
NAVY, ORANGE, GREY, MID = "#1F3864", "#C55A11", "#7F7F7F", "#2E75B6"
best = res.iloc[0]["model"]
fig, axes = plt.subplots(1, 3, figsize=(15, 4.6))
ax = axes[0]
for name, colour in [("Logistic regression (frequency + monetary)", GREY), (best, NAVY), ("Rule: days since last order", ORANGE)]:
    fpr, tpr, _ = roc_curve(y_te, scores[name])
    ax.plot(fpr, tpr, color=colour, lw=2, label=f"{name} ({roc_auc_score(y_te, scores[name]):.2f})")
ax.plot([0, 1], [0, 1], color="#BBBBBB", ls="--", lw=1)
ax.set_xlabel("False positive rate"); ax.set_ylabel("True positive rate"); ax.legend(fontsize=7, loc="lower right")
ax.set_title("ROC curve on the test period", loc="left", fontsize=11)
ax = axes[1]
for name, colour in [("Logistic regression (frequency + monetary)", GREY), (best, NAVY)]:
    frac, mean_p = calibration_curve(y_te, scores[name], n_bins=8, strategy="quantile")
    ax.plot(mean_p, frac, "o-", color=colour, lw=2, label=name)
ax.plot([0, 1], [0, 1], color="#BBBBBB", ls="--", lw=1)
ax.set_xlabel("Predicted churn probability"); ax.set_ylabel("Observed churn rate"); ax.legend(fontsize=7)
ax.set_title("Calibration on the test period", loc="left", fontsize=11)
ax = axes[2]
ax.barh(imp["feature"][::-1], imp["importance"][::-1], color=NAVY)
ax.set_xlabel("Importance (gradient boosting)"); ax.set_title("What drives the forecast", loc="left", fontsize=11)
for a in axes:
    a.spines[["top", "right"]].set_visible(False); a.grid(alpha=0.25)
fig.tight_layout()
fig.savefig(os.path.join(here, "figures", "churn_model_evaluation.png"), dpi=150)
print("done")
