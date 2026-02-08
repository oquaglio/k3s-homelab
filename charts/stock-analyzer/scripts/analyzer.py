#!/usr/bin/env python3
"""
Stock Analyzer - Value Investing Metrics Pipeline

Fetches stock fundamentals via yfinance, calculates value investing
metrics (Magic Formula, Piotroski F-Score, composite score), and
stores everything in PostgreSQL for Grafana dashboards.

Metrics calculated:
  - Valuation: P/E, P/B, EV/EBITDA, Earnings Yield, FCF Yield
  - Quality: ROIC, ROE, ROA, margins
  - Health: Debt/Equity, Current Ratio
  - Growth: Revenue growth, Earnings growth
  - Composite: Magic Formula rank, Piotroski F-Score (0-9), Buy/Hold/Sell signal
"""

import os
import sys
import time
import logging
from datetime import date

import yfinance as yf
import pandas as pd
import numpy as np
from sqlalchemy import create_engine, text

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("stock-analyzer")

# ---------------------------------------------------------------------------
# Configuration (all from environment variables, with sane defaults)
# ---------------------------------------------------------------------------
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "homelab")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASS = os.environ.get("DB_PASS", "postgres")
TICKERS_FILE = os.environ.get("TICKERS_FILE", "/config/tickers.txt")
DELAY = float(os.environ.get("DELAY_SECONDS", "1.5"))

DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# ---------------------------------------------------------------------------
# Database schema
# ---------------------------------------------------------------------------
SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS stocks (
    ticker          VARCHAR(10) PRIMARY KEY,
    company_name    VARCHAR(255),
    sector          VARCHAR(100),
    industry        VARCHAR(100),
    updated_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS stock_metrics (
    id                  SERIAL PRIMARY KEY,
    ticker              VARCHAR(10) NOT NULL,
    calc_date           DATE NOT NULL,
    price               NUMERIC,
    market_cap          NUMERIC,
    enterprise_value    NUMERIC,
    -- Valuation
    trailing_pe         NUMERIC,
    forward_pe          NUMERIC,
    price_to_book       NUMERIC,
    ev_to_ebitda        NUMERIC,
    earnings_yield      NUMERIC,
    fcf_yield           NUMERIC,
    -- Quality
    roic                NUMERIC,
    roe                 NUMERIC,
    roa                 NUMERIC,
    gross_margin        NUMERIC,
    operating_margin    NUMERIC,
    net_margin          NUMERIC,
    -- Health
    debt_to_equity      NUMERIC,
    current_ratio       NUMERIC,
    -- Growth
    revenue_growth      NUMERIC,
    earnings_growth     NUMERIC,
    -- Scores
    piotroski_score     INTEGER,
    magic_formula_rank  INTEGER,
    composite_score     NUMERIC,
    signal              VARCHAR(4),
    updated_at          TIMESTAMP DEFAULT NOW(),
    UNIQUE(ticker, calc_date)
);
"""


def get_tickers():
    """Read ticker list from mounted config file."""
    with open(TICKERS_FILE) as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


def create_tables(engine):
    """Create tables if they don't exist."""
    with engine.begin() as conn:
        for stmt in SCHEMA_SQL.split(";"):
            stmt = stmt.strip()
            if stmt:
                conn.execute(text(stmt))
    log.info("Database tables ready")


def safe(val):
    """Return None for NaN/Inf values, pass through everything else."""
    if val is None:
        return None
    try:
        if pd.isna(val) or np.isinf(val):
            return None
    except (TypeError, ValueError):
        pass
    return float(val)


def get_stmt_value(df, keys, col=0):
    """Safely get a value from a financial statement DataFrame.

    Tries each key in order, returns the value from the given column index.
    Returns None if not found or NaN.
    """
    if df is None or df.empty:
        return None
    for key in keys if isinstance(keys, list) else [keys]:
        if key in df.index:
            val = df.loc[key].iloc[col]
            if not pd.isna(val):
                return float(val)
    return None


# ---------------------------------------------------------------------------
# ROIC calculation
# ---------------------------------------------------------------------------
def calculate_roic(ticker_obj, info):
    """Calculate Return on Invested Capital.

    ROIC = EBIT / Invested Capital
    Invested Capital = Total Assets - Current Liabilities - Cash

    Falls back to ROE from ticker.info if statements are unavailable.
    """
    try:
        fin = ticker_obj.financials
        bs = ticker_obj.balance_sheet

        if fin is not None and not fin.empty and bs is not None and not bs.empty:
            ebit = get_stmt_value(fin, ["EBIT", "Operating Income"])
            total_assets = get_stmt_value(bs, ["Total Assets"])
            cur_liab = get_stmt_value(
                bs, ["Current Liabilities", "Total Current Liabilities"]
            )
            cash = get_stmt_value(
                bs,
                [
                    "Cash And Cash Equivalents",
                    "Cash Cash Equivalents And Short Term Investments",
                ],
            )

            if ebit is not None and total_assets is not None and cur_liab is not None:
                cash = cash or 0
                invested_capital = total_assets - cur_liab - cash
                if invested_capital > 0:
                    return ebit / invested_capital
    except Exception as e:
        log.debug(f"ROIC from statements failed: {e}")

    # Fallback to ROE (imperfect but better than nothing)
    roe = info.get("returnOnEquity")
    return safe(roe)


# ---------------------------------------------------------------------------
# Piotroski F-Score (0-9)
# ---------------------------------------------------------------------------
def calculate_piotroski(ticker_obj, info):
    """Calculate Piotroski F-Score.

    9 binary tests across three categories:
      Profitability (4 pts): positive ROA, positive OCF, improving ROA, OCF > NI
      Leverage (3 pts): decreasing debt, improving current ratio, no dilution
      Efficiency (2 pts): improving gross margin, improving asset turnover
    """
    score = 0

    try:
        fin = ticker_obj.financials
        bs = ticker_obj.balance_sheet
        cf = ticker_obj.cashflow

        has_multi_year = (
            fin is not None
            and not fin.empty
            and len(fin.columns) >= 2
            and bs is not None
            and not bs.empty
            and len(bs.columns) >= 2
        )

        # ---- Profitability (4 points) ----

        # 1. Positive ROA
        roa = info.get("returnOnAssets")
        if roa is not None and not pd.isna(roa) and roa > 0:
            score += 1

        # 2. Positive operating cash flow
        ocf = get_stmt_value(
            cf, ["Operating Cash Flow", "Total Cash From Operating Activities"]
        )
        if ocf is not None and ocf > 0:
            score += 1

        # 3. ROA improving vs prior year
        if has_multi_year:
            ni_curr = get_stmt_value(fin, ["Net Income"], col=0)
            ni_prev = get_stmt_value(fin, ["Net Income"], col=1)
            ta_curr = get_stmt_value(bs, ["Total Assets"], col=0)
            ta_prev = get_stmt_value(bs, ["Total Assets"], col=1)
            if all(
                v is not None and v > 0 for v in [ni_curr, ta_curr, ni_prev, ta_prev]
            ):
                if (ni_curr / ta_curr) > (ni_prev / ta_prev):
                    score += 1

        # 4. Cash flow from operations > Net Income (accrual quality)
        ni = get_stmt_value(fin, ["Net Income"])
        if ocf is not None and ni is not None and ocf > ni:
            score += 1

        # ---- Leverage, Liquidity (3 points) ----

        # 5. Decreasing long-term debt
        if has_multi_year:
            debt_curr = get_stmt_value(
                bs, ["Long Term Debt", "Long Term Debt And Capital Lease Obligation"], col=0
            )
            debt_prev = get_stmt_value(
                bs, ["Long Term Debt", "Long Term Debt And Capital Lease Obligation"], col=1
            )
            if debt_curr is not None and debt_prev is not None:
                if debt_curr <= debt_prev:
                    score += 1

        # 6. Improving current ratio
        if has_multi_year:
            ca_curr = get_stmt_value(bs, ["Current Assets", "Total Current Assets"], col=0)
            ca_prev = get_stmt_value(bs, ["Current Assets", "Total Current Assets"], col=1)
            cl_curr = get_stmt_value(bs, ["Current Liabilities", "Total Current Liabilities"], col=0)
            cl_prev = get_stmt_value(bs, ["Current Liabilities", "Total Current Liabilities"], col=1)
            if all(v is not None and v > 0 for v in [ca_curr, cl_curr, ca_prev, cl_prev]):
                if (ca_curr / cl_curr) > (ca_prev / cl_prev):
                    score += 1

        # 7. No share dilution
        if has_multi_year:
            sh_curr = get_stmt_value(bs, ["Share Issued", "Ordinary Shares Number"], col=0)
            sh_prev = get_stmt_value(bs, ["Share Issued", "Ordinary Shares Number"], col=1)
            if sh_curr is not None and sh_prev is not None:
                if sh_curr <= sh_prev:
                    score += 1

        # ---- Operating Efficiency (2 points) ----

        # 8. Improving gross margin
        if has_multi_year:
            gp_curr = get_stmt_value(fin, ["Gross Profit"], col=0)
            gp_prev = get_stmt_value(fin, ["Gross Profit"], col=1)
            rev_curr = get_stmt_value(fin, ["Total Revenue"], col=0)
            rev_prev = get_stmt_value(fin, ["Total Revenue"], col=1)
            if all(v is not None and v > 0 for v in [gp_curr, rev_curr, gp_prev, rev_prev]):
                if (gp_curr / rev_curr) > (gp_prev / rev_prev):
                    score += 1

        # 9. Improving asset turnover
        if has_multi_year:
            rev_curr = get_stmt_value(fin, ["Total Revenue"], col=0)
            rev_prev = get_stmt_value(fin, ["Total Revenue"], col=1)
            ta_curr = get_stmt_value(bs, ["Total Assets"], col=0)
            ta_prev = get_stmt_value(bs, ["Total Assets"], col=1)
            if all(v is not None and v > 0 for v in [rev_curr, ta_curr, rev_prev, ta_prev]):
                if (rev_curr / ta_curr) > (rev_prev / ta_prev):
                    score += 1

    except Exception as e:
        log.debug(f"Piotroski error: {e}")

    return score


# ---------------------------------------------------------------------------
# Fetch data for a single ticker
# ---------------------------------------------------------------------------
def fetch_ticker_data(symbol):
    """Fetch all fundamental data for one ticker and return a metrics dict."""
    t = yf.Ticker(symbol)
    info = t.info

    if not info or info.get("regularMarketPrice") is None:
        log.warning(f"  {symbol}: no data available, skipping")
        return None

    price = safe(info.get("currentPrice")) or safe(info.get("regularMarketPrice"))
    market_cap = safe(info.get("marketCap"))
    ev = safe(info.get("enterpriseValue"))
    ebitda = safe(info.get("ebitda"))
    fcf = safe(info.get("freeCashflow"))

    metrics = {
        "company_name": info.get("longName", ""),
        "sector": info.get("sector", ""),
        "industry": info.get("industry", ""),
        "price": price,
        "market_cap": market_cap,
        "enterprise_value": ev,
        # Valuation (pre-calculated by yfinance)
        "trailing_pe": safe(info.get("trailingPE")),
        "forward_pe": safe(info.get("forwardPE")),
        "price_to_book": safe(info.get("priceToBook")),
        "ev_to_ebitda": safe(info.get("enterpriseToEbitda")),
        # Quality
        "roe": safe(info.get("returnOnEquity")),
        "roa": safe(info.get("returnOnAssets")),
        "gross_margin": safe(info.get("grossMargins")),
        "operating_margin": safe(info.get("operatingMargins")),
        "net_margin": safe(info.get("profitMargins")),
        # Health
        "debt_to_equity": safe(info.get("debtToEquity")),
        "current_ratio": safe(info.get("currentRatio")),
        # Growth
        "revenue_growth": safe(info.get("revenueGrowth")),
        "earnings_growth": safe(info.get("earningsGrowth")),
    }

    # Earnings Yield = EBITDA / Enterprise Value
    if ebitda and ev and ev > 0:
        metrics["earnings_yield"] = ebitda / ev
    else:
        metrics["earnings_yield"] = None

    # Free Cash Flow Yield = FCF / Market Cap
    if fcf and market_cap and market_cap > 0:
        metrics["fcf_yield"] = fcf / market_cap
    else:
        metrics["fcf_yield"] = None

    # ROIC (from financial statements, with fallback)
    metrics["roic"] = calculate_roic(t, info)

    # Piotroski F-Score (0-9)
    metrics["piotroski_score"] = calculate_piotroski(t, info)

    return metrics


# ---------------------------------------------------------------------------
# Database operations
# ---------------------------------------------------------------------------
def upsert_stock(engine, ticker, m):
    """Insert or update stock master record."""
    with engine.begin() as conn:
        conn.execute(
            text("""
                INSERT INTO stocks (ticker, company_name, sector, industry, updated_at)
                VALUES (:ticker, :name, :sector, :industry, NOW())
                ON CONFLICT (ticker) DO UPDATE SET
                    company_name = EXCLUDED.company_name,
                    sector = EXCLUDED.sector,
                    industry = EXCLUDED.industry,
                    updated_at = NOW()
            """),
            {"ticker": ticker, "name": m["company_name"], "sector": m["sector"], "industry": m["industry"]},
        )


def upsert_metrics(engine, ticker, m):
    """Insert or update today's metrics for a ticker."""
    today = date.today()
    params = {"ticker": ticker, "calc_date": today}
    cols = [
        "price", "market_cap", "enterprise_value",
        "trailing_pe", "forward_pe", "price_to_book", "ev_to_ebitda",
        "earnings_yield", "fcf_yield",
        "roic", "roe", "roa", "gross_margin", "operating_margin", "net_margin",
        "debt_to_equity", "current_ratio",
        "revenue_growth", "earnings_growth",
        "piotroski_score",
    ]
    for col in cols:
        params[col] = m.get(col)

    col_list = ", ".join(cols)
    val_list = ", ".join(f":{c}" for c in cols)
    update_list = ", ".join(f"{c} = EXCLUDED.{c}" for c in cols)

    with engine.begin() as conn:
        conn.execute(
            text(f"""
                INSERT INTO stock_metrics (ticker, calc_date, {col_list}, updated_at)
                VALUES (:ticker, :calc_date, {val_list}, NOW())
                ON CONFLICT (ticker, calc_date) DO UPDATE SET
                    {update_list}, updated_at = NOW()
            """),
            params,
        )


# ---------------------------------------------------------------------------
# Ranking and composite score
# ---------------------------------------------------------------------------
def calculate_rankings(engine):
    """Calculate Magic Formula ranks and composite buy/sell scores."""
    today = date.today()

    df = pd.read_sql(
        text("""
            SELECT ticker, earnings_yield, roic, fcf_yield,
                   debt_to_equity, revenue_growth, gross_margin, piotroski_score
            FROM stock_metrics
            WHERE calc_date = :today
        """),
        engine,
        params={"today": today},
    )

    if df.empty:
        log.warning("No metrics for today, skipping ranking")
        return

    # -- Magic Formula: rank by ROIC + Earnings Yield --
    roic_rank = df["roic"].rank(ascending=False, na_option="bottom")
    ey_rank = df["earnings_yield"].rank(ascending=False, na_option="bottom")
    df["magic_formula_rank"] = (roic_rank + ey_rank).rank(ascending=True).astype(int)

    # -- Percentile ranks for each component (0-100, higher = better) --
    def pct(series, ascending=False):
        return series.rank(ascending=ascending, na_option="bottom", pct=True) * 100

    mf_pct = pct(-(roic_rank + ey_rank))                    # Lower combined rank = better
    pio_pct = pct(df["piotroski_score"])
    fcf_pct = pct(df["fcf_yield"])
    de_pct = pct(df["debt_to_equity"], ascending=True)       # Lower debt = better
    rg_pct = pct(df["revenue_growth"])
    gm_pct = pct(df["gross_margin"])

    # -- Weighted composite score --
    # Weights are read from env (set by values.yaml) with defaults
    w_mf = float(os.environ.get("W_MAGIC_FORMULA", "0.30"))
    w_pio = float(os.environ.get("W_PIOTROSKI", "0.25"))
    w_fcf = float(os.environ.get("W_FCF_YIELD", "0.15"))
    w_de = float(os.environ.get("W_DEBT_EQUITY", "0.10"))
    w_rg = float(os.environ.get("W_REVENUE_GROWTH", "0.10"))
    w_gm = float(os.environ.get("W_GROSS_MARGIN", "0.10"))

    df["composite_score"] = (
        mf_pct * w_mf + pio_pct * w_pio + fcf_pct * w_fcf
        + de_pct * w_de + rg_pct * w_rg + gm_pct * w_gm
    )

    # -- Buy / Hold / Sell signal --
    df["signal"] = df["composite_score"].apply(
        lambda x: "BUY" if x >= 70 else ("SELL" if x <= 30 else "HOLD")
    )

    # -- Write back to database --
    with engine.begin() as conn:
        for _, row in df.iterrows():
            conn.execute(
                text("""
                    UPDATE stock_metrics
                    SET magic_formula_rank = :mf, composite_score = :score,
                        signal = :signal, updated_at = NOW()
                    WHERE ticker = :ticker AND calc_date = :today
                """),
                {
                    "ticker": row["ticker"],
                    "today": today,
                    "mf": int(row["magic_formula_rank"]),
                    "score": round(float(row["composite_score"]), 2),
                    "signal": row["signal"],
                },
            )

    # -- Print summary --
    top = df.nlargest(10, "composite_score")[
        ["ticker", "composite_score", "signal", "magic_formula_rank", "piotroski_score"]
    ]
    log.info(f"\n{'='*60}")
    log.info("Top 10 Stocks by Composite Score:")
    log.info(f"{'='*60}")
    log.info(f"\n{top.to_string(index=False)}")

    buys = len(df[df["signal"] == "BUY"])
    holds = len(df[df["signal"] == "HOLD"])
    sells = len(df[df["signal"] == "SELL"])
    log.info(f"\nSignals: {buys} BUY | {holds} HOLD | {sells} SELL")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    log.info("Stock Analyzer starting...")

    engine = create_engine(DATABASE_URL)
    create_tables(engine)

    tickers = get_tickers()
    log.info(f"Processing {len(tickers)} tickers...")

    success = 0
    errors = 0

    for i, symbol in enumerate(tickers, 1):
        try:
            log.info(f"[{i}/{len(tickers)}] {symbol}")
            metrics = fetch_ticker_data(symbol)

            if metrics:
                upsert_stock(engine, symbol, metrics)
                upsert_metrics(engine, symbol, metrics)
                pio = metrics.get("piotroski_score", "?")
                roic = metrics.get("roic")
                roic_str = f"{roic:.1%}" if roic else "N/A"
                log.info(f"  -> F-Score: {pio}/9, ROIC: {roic_str}")
                success += 1
            else:
                errors += 1

            if i < len(tickers):
                time.sleep(DELAY)

        except Exception as e:
            log.error(f"  Error: {e}")
            errors += 1

    log.info(f"\nFetch complete: {success} ok, {errors} failed")

    log.info("Calculating rankings and composite scores...")
    calculate_rankings(engine)

    log.info("Stock Analyzer finished!")


if __name__ == "__main__":
    main()
