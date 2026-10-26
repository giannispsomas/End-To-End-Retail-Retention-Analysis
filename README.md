# End-To-End Retail Retention Analysis

An end-to-end analysis of about 1M transactions from a UK online retailer (December 2009 to December 2011). The project takes raw sales data through SQL Server, Python and Power BI to answer one question: **where does revenue come from, and how much of it is at risk?**

**Tools:** SQL Server (T-SQL) · Python (Jupyter) · Power BI (DAX)

**Start here:** [Video walkthrough (3 min)](https://youtu.be/I_UvFsbfLRI) · [Case study](Case_Study.md) · [Dashboard report (PDF)](power_bi/Retention_Analysis.pdf)

### At a glance

- **72% of customers are repeat buyers, and they generate 97% of revenue.** The median time to a second order is 57 days, so a follow-up around day 30 is the clearest lever.
- **51% of identified customers have gone quiet for 90+ days, holding £3.30M (17%) of historical revenue.** The 589 who lapsed 91 to 180 days ago are the most recoverable.
- **Revenue is concentrated:** the UK is 85.5% of sales and September to November is 29% of the year.

**Skills shown:** data profiling and cleaning in T-SQL · star-schema modelling and reporting views · RFM segmentation with K-Means · cohort retention analysis · logistic-regression churn scoring · DAX measures and a six-page Power BI dashboard · documenting assumptions and limits honestly.

![Business Overview](power_bi/images/1_Business_Overview.png)

## Key Findings and Recommendations

Between December 2009 and December 2011 the business generated **£19.64M** from **39,516 orders** and **5,852 identified customers** (average order value £497.09; the last month is partial).

The full findings, the six ranked recommendations and the limits of the analysis are in the **[case study](Case_Study.md)**. The recommendations are hypotheses drawn from the data and none has been tested. See [Assumptions_and_Limitations.md](docs/Assumptions_and_Limitations.md).

## Dashboard

The Power BI report has six pages: Business Overview, Products, Repeat Customer Behavior, Customer Segmentation, Cohort and Retention, and Churn Risk.

| | |
|---|---|
| ![Repeat Customer Behavior](power_bi/images/3_Repeat_Customer_Behavior.png) | ![Churn Risk](power_bi/images/6_Churn_Risk.png) |

**Can't open Power BI?** The full six-page report is available as a PDF: [power_bi/Retention_Analysis.pdf](power_bi/Retention_Analysis.pdf).

A page-by-page walkthrough with the measures behind each visual is in [Report_Guide.md](docs/Report_Guide.md).

## Project Overview

**Business problem:** How can the company use its transaction data to identify repeat customers, understand the variables behind repeat purchasing, and use these insights, together with top-selling product data, to improve marketing and operations strategy?

**Approach**

1. **SQL Server:** profile and clean the raw data, build a star schema, and create reporting views ([sql/](sql/)).
2. **Python:** RFM segmentation with K-Means clustering, cohort retention, churn prediction, statistical tests, a forward-looking churn model, a revenue forecast and a lifetime value model ([python/](python/)).
3. **Power BI:** a six-page interactive dashboard on top of the SQL views and Python outputs ([power_bi/](power_bi/)).

## Repository Structure

```
End-To-End-Retail-Retention-Analysis/
├── README.md                        Project overview (this file)
├── Case_Study.md                    The project as a story: question, findings, actions, limits
├── Executive_Summary.pdf            One-page summary for business stakeholders (print-friendly)
├── Executive_Summary_Slides.pptx    The same story as 7 slides
├── requirements.txt                 Python dependencies
├── LICENSE                          MIT license
├── docs/                            Supporting documentation
│   ├── data_profiling.md            Profiling of the raw data
│   ├── data_cleaning.md             Cleaning steps and row counts
│   ├── star_schema.md               Star schema design and reporting layer
│   ├── star_schema_diagram.png      Entity-relationship diagram
│   ├── Business_Questions.md        Business questions, methods and findings
│   ├── DAX_Measures.md              Every DAX measure with formula and purpose
│   ├── Report_Guide.md              Page-by-page dashboard walkthrough
│   ├── Statistical_Tests.md         Tests and intervals for the main findings
│   ├── Churn_Model_Evaluation.md    Forward-looking churn model, tested on a later period
│   ├── Sensitivity_and_Forecast.md  Churn-threshold sensitivity and revenue forecast
│   ├── Customer_Lifetime_Value.md   BG/NBD and Gamma-Gamma lifetime value
│   └── Assumptions_and_Limitations.md   Definitions, assumptions and limits
├── sql/                             T-SQL scripts (profiling, cleaning, star schema, RFM, business questions)
├── python/                          Notebooks and analysis scripts
│   ├── rfmcustseg.ipynb             RFM segmentation and K-Means clustering
│   ├── coh_ret_analysis.ipynb       Cohort retention
│   ├── churn_regr.ipynb             Churn prediction
│   ├── 01_statistical_tests.py      Tests and bootstrap intervals
│   ├── 02_churn_model_evaluation.py Forward-looking churn model and comparison
│   ├── 03_sensitivity_and_forecast.py  Threshold sensitivity and revenue forecast
│   ├── 04_customer_lifetime_value.py   BG/NBD and Gamma-Gamma
│   ├── results/                     CSV results of the four scripts
│   └── figures/                     Charts of the four scripts
└── power_bi/                        Power BI report and dashboard screenshots
    ├── Retention_Analysis.pbix      Power BI report
    ├── Retention_Analysis.pdf       The same report exported as a PDF
    └── images/                      One screenshot per dashboard page
```

## Documentation

| Document | What it covers |
|---|---|
| [Case_Study.md](Case_Study.md) | The project as a story: question, data fixes, findings, ranked actions, and how far to trust the churn score |
| [Executive_Summary.pdf](Executive_Summary.pdf) | One-page summary for stakeholders: bottom line, ranked actions, findings, and limits |
| [Executive_Summary_Slides.pptx](Executive_Summary_Slides.pptx) | A 7-slide presentation of the question, findings, ranked actions and limits |
| [data_profiling.md](docs/data_profiling.md) | Data quality profile of the raw dataset |
| [data_cleaning.md](docs/data_cleaning.md) | Cleaning and transformation steps, with row counts |
| [star_schema.md](docs/star_schema.md) | Fact and dimension tables, keys, the ER diagram, and the `rpt` reporting layer |
| [Business_Questions.md](docs/Business_Questions.md) | Each business question, its method, and its finding |
| [DAX_Measures.md](docs/DAX_Measures.md) | Every measure and calculated column, with formulas |
| [Report_Guide.md](docs/Report_Guide.md) | The six dashboard pages and how to read them |
| [Statistical_Tests.md](docs/Statistical_Tests.md) | Tests and bootstrap intervals for the main findings: spend, time to a second order, seasonality |
| [Churn_Model_Evaluation.md](docs/Churn_Model_Evaluation.md) | A forward-looking churn model tested on a later period, compared with a random forest and gradient boosting |
| [Sensitivity_and_Forecast.md](docs/Sensitivity_and_Forecast.md) | How the revenue at risk changes with the churn threshold, and a six-month revenue forecast with ranges |
| [Customer_Lifetime_Value.md](docs/Customer_Lifetime_Value.md) | BG/NBD and Gamma-Gamma lifetime value, validated on a hold-out period |
| [Assumptions_and_Limitations.md](docs/Assumptions_and_Limitations.md) | Definitions, assumptions, and what the analysis cannot conclude |

## Dataset

- **Source:** [Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii), UCI Machine Learning Repository, licensed CC BY 4.0. Donated by Daqing Chen.
- **Sheets:** two sheets, "Year 2009-2010" and "Year 2010-2011", combined into one table (one row per product line item within an invoice).
- **Size:** 43.5 MB, 1,067,371 rows across the two sheets. The sheets overlap in December 2010 (the second sheet starts in the month the first one ends), so 22,523 rows appear on both. One copy was removed when the sheets were combined, and the raw SQL table therefore holds 1,044,848 rows.
- **Columns:** Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer ID, Country.

> `online_retail_II.xlsx` is excluded from version control through `.gitignore` because of its size. Download it from the link above and place it in the project root before running any scripts.

## Definitions and Assumptions

The full list is in [Assumptions_and_Limitations.md](docs/Assumptions_and_Limitations.md). The key ones:

- Invoices starting with "C" are cancellations or returns and are excluded from revenue and repeat-purchase calculations.
- Guest checkouts (no Customer ID, 13.1% of revenue) are excluded from customer-level metrics.
- A **repeat customer** has two or more distinct, non-cancelled invoices.
- A customer is **churned** after 90 or more days without a purchase.
- Prices are unit selling prices in GBP. There is no cost data, so margin and profitability are out of scope.

## Limitations

The full list is in [Assumptions_and_Limitations.md](docs/Assumptions_and_Limitations.md). The ones that matter most:

- **The churn score is not a forecast.** It describes who looks like a lapsed customer today (ROC-AUC 0.77, only slightly above a simple "fewer orders" rule). It is useful for ranking outreach.
- **"Revenue at risk" (£3.30M) is past spend,** not what a win-back campaign would recover. The 90-day rule can also label seasonal buyers as churned, so the real figure is probably lower.
- **Two years of data** show only two seasonal cycles, and December 2011 is a partial month.
- **13.1% of revenue is guest checkouts,** which cannot be tied to a customer, so customer-level results describe 86.9% of revenue.
- **The findings are descriptive, not causal,** and there is no cost data, so this is revenue, not profit. The recommendations are hypotheses that have not been tested.

## Reproducing the Project

### Environment
- SQL Server 2025 Express
- SQL Server Management Studio 22.9.5
- Python 3.14 (developed on 3.14.6) with the packages in `requirements.txt`
- Power BI Desktop 2.156.951.0 64-bit (July 2026) or later

### Steps

1. **Get the data.** Download `online_retail_II.xlsx` (see [Dataset](#dataset)).
2. **Load the data into SQL Server.** The data was imported manually with the **Import Flat File** wizard in SQL Server Management Studio; there is no import script. Create the raw table this way before running the SQL scripts.
3. **Run the SQL scripts** in [sql/](sql/) in numbered order, from `01_data_profiling.sql` through `04_rfm_table.sql`. `05_business_questions.sql` holds the analysis queries.
4. **Set up Python:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate       # Windows: venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   ```
5. **Run the notebooks** in [python/](python/): RFM and K-Means clustering, cohort retention, and churn prediction. Then run the four analysis scripts from the repository root, for example `python python/01_statistical_tests.py`. They read the `rpt` views of the `OnlineRetailII` database and write to `python/results/` and `python/figures/`.
6. **Open the dashboard** in [power_bi/](power_bi/) with Power BI Desktop.

### Connecting Power BI to your own database

1. In Power BI Desktop, go to **Home → Get Data → SQL Server**.
2. Enter your server (for example `localhost\SQLEXPRESS`) and your database name.
3. Choose **Import** mode. DirectQuery is unnecessary at this data size.
4. Choose **Windows authentication**.
5. Select the reporting views and tables, then click **Load**.

The report was built with Windows authentication, so it stores no passwords or credentials. If you share your own copy, clear stored credentials first (File → Options and settings → Data source settings).

## About the author

Built by **Giannis Psomas**, using SQL Server, Python and Power BI to turn raw transaction data into retention insights and recommendations. Questions or feedback are welcome.

- LinkedIn: [giannispsomas](https://www.linkedin.com/in/giannispsomas)
- GitHub: [giannispsomas](https://github.com/giannispsomas)

## License

The code in this repository is released under the [MIT License](LICENSE). The dataset is not included; it is licensed separately under CC BY 4.0 by its authors (see [Dataset](#dataset)).
