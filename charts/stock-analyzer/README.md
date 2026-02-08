# Stock Analyzer

A Kubernetes CronJob that fetches stock fundamentals, calculates value investing metrics, and stores results in PostgreSQL for Grafana dashboards.

## What It Does

Every weekday at 10 PM UTC (after US market close), the analyzer:

1. Fetches fundamental data for each ticker via [yfinance](https://github.com/ranaroussi/yfinance) (free, no API key)
2. Calculates 20+ metrics per stock
3. Ranks all stocks against each other
4. Computes a composite score (0-100) and a BUY / HOLD / SELL signal
5. Stores everything in PostgreSQL (your existing `homelab` database)

## Metrics Calculated

### Valuation (is it cheap?)

| Metric | Source | What It Means |
|--------|--------|---------------|
| Trailing P/E | yfinance | Price relative to last 12 months earnings |
| Forward P/E | yfinance | Price relative to estimated future earnings |
| Price/Book | yfinance | Price relative to book value (< 1.0 = below book) |
| EV/EBITDA | yfinance | Enterprise value relative to operating earnings |
| Earnings Yield | calculated | EBITDA / Enterprise Value (inverse of EV/EBITDA, higher = cheaper) |
| FCF Yield | calculated | Free Cash Flow / Market Cap (higher = more cash per dollar invested) |

### Quality (is it a good business?)

| Metric | Source | What It Means |
|--------|--------|---------------|
| ROIC | calculated | Return on Invested Capital = EBIT / (Assets - Current Liabilities - Cash) |
| ROE | yfinance | Return on Equity |
| ROA | yfinance | Return on Assets |
| Gross Margin | yfinance | Revenue kept after cost of goods |
| Operating Margin | yfinance | Revenue kept after operating expenses |
| Net Margin | yfinance | Revenue kept after all expenses |

### Financial Health (is it safe?)

| Metric | Source | What It Means |
|--------|--------|---------------|
| Debt/Equity | yfinance | Total debt relative to equity (lower = less leveraged) |
| Current Ratio | yfinance | Current assets / current liabilities (> 1.5 = healthy) |

### Growth

| Metric | Source | What It Means |
|--------|--------|---------------|
| Revenue Growth | yfinance | Year-over-year revenue change |
| Earnings Growth | yfinance | Year-over-year earnings change |

## Composite Scores

### Magic Formula (Joel Greenblatt)

Ranks stocks on two factors and combines them:
- **ROIC rank** (high ROIC = good business)
- **Earnings Yield rank** (high yield = cheap price)

Low combined rank = a good business at a cheap price.

### Piotroski F-Score (0-9)

Nine binary yes/no tests across three categories:

**Profitability (4 points):**
1. Positive ROA
2. Positive operating cash flow
3. ROA improving vs prior year
4. Cash flow from operations > Net Income

**Leverage & Liquidity (3 points):**
5. Long-term debt decreasing
6. Current ratio improving
7. No new shares issued (no dilution)

**Operating Efficiency (2 points):**
8. Gross margin improving
9. Asset turnover improving

**Interpretation:** 8-9 = strong, 5-7 = average, 0-4 = weak

### Composite Score (0-100)

Weighted combination of all factors, producing a single number:

| Component | Default Weight | What It Captures |
|-----------|---------------|------------------|
| Magic Formula rank | 30% | Value + quality combined |
| Piotroski F-Score | 25% | Financial strength |
| FCF Yield | 15% | Cash generation |
| Debt/Equity | 10% | Financial safety |
| Revenue Growth | 10% | Growth trajectory |
| Gross Margin | 10% | Business quality |

**Signal:**
- **BUY** = composite score >= 70
- **HOLD** = composite score 31-69
- **SELL** = composite score <= 30

## Configuration

Edit `values.yaml` to customize:

```yaml
# Change the schedule (cron format)
schedule: "0 22 * * 1-5"

# Add or remove tickers
tickers:
  - AAPL
  - MSFT
  - GOOGL
  # ... add your own

# Tune the composite score weights (must sum to 1.0)
weights:
  magicFormula: 0.30
  piotroski: 0.25
  fcfYield: 0.15
  debtEquity: 0.10
  revenueGrowth: 0.10
  grossMargin: 0.10
```

## Usage

### Deploy
```bash
helm upgrade --install stock-analyzer ./charts/stock-analyzer --namespace default
```

### Trigger a Manual Run
```bash
kubectl create job --from=cronjob/stock-analyzer-stock-analyzer manual-run
```

### Watch the Logs
```bash
kubectl logs job/manual-run -f
```

### Query Results via psql
```bash
# Top stocks by composite score
kubectl exec -it deploy/postgresql-postgresql -n postgresql -- \
  psql -U postgres -d homelab -c \
  "SELECT ticker, composite_score, signal, magic_formula_rank, piotroski_score
   FROM stock_metrics
   WHERE calc_date = CURRENT_DATE
   ORDER BY composite_score DESC"

# All BUY signals
kubectl exec -it deploy/postgresql-postgresql -n postgresql -- \
  psql -U postgres -d homelab -c \
  "SELECT ticker, composite_score, roic, earnings_yield, piotroski_score
   FROM stock_metrics
   WHERE calc_date = CURRENT_DATE AND signal = 'BUY'
   ORDER BY composite_score DESC"

# Track a stock's score over time
kubectl exec -it deploy/postgresql-postgresql -n postgresql -- \
  psql -U postgres -d homelab -c \
  "SELECT calc_date, composite_score, signal, price
   FROM stock_metrics
   WHERE ticker = 'AAPL'
   ORDER BY calc_date DESC
   LIMIT 30"
```

### Delete a Manual Job
```bash
kubectl delete job manual-run
```

## Grafana Integration

Add PostgreSQL as a Grafana datasource to build dashboards:

1. Open Grafana at http://localhost:30080
2. Go to **Connections > Data Sources > Add data source**
3. Select **PostgreSQL**
4. Configure:
   - Host: `postgresql-postgresql.postgresql.svc.cluster.local:5432`
   - Database: `homelab`
   - User: `postgres`
   - Password: `postgres`
   - TLS/SSL Mode: `disable`
5. Click **Save & Test**

### Example Grafana Queries

**Top 10 stocks table:**
```sql
SELECT ticker, composite_score, signal, magic_formula_rank,
       piotroski_score, roic, earnings_yield, trailing_pe
FROM stock_metrics
WHERE calc_date = CURRENT_DATE
ORDER BY composite_score DESC
LIMIT 10
```

**Composite score over time (time series):**
```sql
SELECT calc_date AS time, composite_score
FROM stock_metrics
WHERE ticker = 'AAPL'
ORDER BY calc_date
```

**Signal distribution (pie chart):**
```sql
SELECT signal, COUNT(*) as count
FROM stock_metrics
WHERE calc_date = CURRENT_DATE
GROUP BY signal
```

**Sector average scores (bar chart):**
```sql
SELECT s.sector, AVG(m.composite_score) as avg_score
FROM stock_metrics m
JOIN stocks s ON m.ticker = s.ticker
WHERE m.calc_date = CURRENT_DATE
GROUP BY s.sector
ORDER BY avg_score DESC
```

## Database Schema

Two tables are created automatically in the `homelab` database:

- **`stocks`** - Master list of tickers with company name, sector, industry
- **`stock_metrics`** - Daily metrics with one row per ticker per date (unique on `ticker + calc_date`)

## Architecture

```
CronJob (10 PM UTC, Mon-Fri)
    |
    v
python:3.12-slim container
    |-- pip install yfinance pandas sqlalchemy psycopg2-binary numpy
    |-- python /scripts/analyzer.py
    |
    v
yfinance API (Yahoo Finance, free)
    |
    v
pandas (calculate metrics, rank stocks)
    |
    v
PostgreSQL (homelab DB, existing cluster service)
    |
    v
Grafana (add PG datasource, build dashboards)
```

## How It Works Under the Hood

1. The CronJob creates a pod with a `python:3.12-slim` image
2. It installs Python dependencies via pip (~15 seconds)
3. The analyzer script is mounted from a ConfigMap
4. For each ticker, it calls `yfinance.Ticker(symbol).info` and `.financials` / `.balance_sheet` / `.cashflow`
5. It calculates ROIC from financial statements (falls back to ROE if statements are unavailable)
6. It runs all 9 Piotroski F-Score tests using current vs prior year financial statements
7. After all tickers are processed, it ranks them against each other and computes composite scores
8. Results are upserted into PostgreSQL (safe to re-run multiple times per day)
9. The pod exits and is cleaned up by Kubernetes
