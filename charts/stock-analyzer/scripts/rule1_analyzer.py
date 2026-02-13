#!/usr/bin/env python3
"""
Rule #1 Investing Analyzer — Phil Town's Value Investing Metrics

Fetches multi-year financial data via yfinance and calculates:
  - Annual time-series: ROIC, BVPS, EPS, Revenue, FCF, Avg Price, Avg PE
  - YoY growth rates for each metric
  - CAGRs: full range (earliest → most recent annual) and recent (2nd-to-last → TTM)
  - Snapshot metrics: ROA, ROE, Dividends, Total Liabilities, Debt/Equity,
    Current Ratio, Quick Ratio

Results are stored in two PostgreSQL tables:
  - rule1_annual  (one row per ticker per fiscal year)
  - rule1_summary (one row per ticker per analysis date)
"""

import os
import sys
import time
import logging
from datetime import date, timedelta

import yfinance as yf
import pandas as pd
import numpy as np
from sqlalchemy import create_engine, text

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("rule1-analyzer")

# ---------------------------------------------------------------------------
# Configuration
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
CREATE TABLE IF NOT EXISTS rule1_annual (
    id                      SERIAL PRIMARY KEY,
    ticker                  VARCHAR(10) NOT NULL,
    fiscal_year             INTEGER NOT NULL,
    roic_pct                NUMERIC,
    book_value_per_share    NUMERIC,
    earnings_per_share      NUMERIC,
    revenue_mil             NUMERIC,
    fcf_mil                 NUMERIC,
    avg_share_price         NUMERIC,
    avg_pe                  NUMERIC,
    roic_yoy               NUMERIC,
    bvps_yoy               NUMERIC,
    eps_yoy                NUMERIC,
    revenue_yoy            NUMERIC,
    fcf_yoy                NUMERIC,
    price_yoy              NUMERIC,
    pe_yoy                 NUMERIC,
    updated_at             TIMESTAMP DEFAULT NOW(),
    UNIQUE(ticker, fiscal_year)
);

CREATE TABLE IF NOT EXISTS rule1_summary (
    id                      SERIAL PRIMARY KEY,
    ticker                  VARCHAR(10) NOT NULL,
    calc_date               DATE NOT NULL,
    years_of_data           INTEGER,
    roic_cagr_full          NUMERIC,
    bvps_cagr_full          NUMERIC,
    eps_cagr_full           NUMERIC,
    revenue_cagr_full       NUMERIC,
    fcf_cagr_full           NUMERIC,
    price_cagr_full         NUMERIC,
    pe_cagr_full            NUMERIC,
    roic_cagr_recent        NUMERIC,
    bvps_cagr_recent        NUMERIC,
    eps_cagr_recent         NUMERIC,
    revenue_cagr_recent     NUMERIC,
    fcf_cagr_recent         NUMERIC,
    price_cagr_recent       NUMERIC,
    pe_cagr_recent          NUMERIC,
    roic_ttm                NUMERIC,
    bvps_ttm                NUMERIC,
    eps_ttm                 NUMERIC,
    revenue_ttm_mil         NUMERIC,
    fcf_ttm_mil             NUMERIC,
    price_current           NUMERIC,
    pe_ttm                  NUMERIC,
    roa_pct                 NUMERIC,
    roe_pct                 NUMERIC,
    dividends_ttm           NUMERIC,
    dividend_yield_pct      NUMERIC,
    total_liabilities       NUMERIC,
    debt_to_equity          NUMERIC,
    current_ratio           NUMERIC,
    quick_ratio             NUMERIC,
    updated_at              TIMESTAMP DEFAULT NOW(),
    UNIQUE(ticker, calc_date)
);
"""


# ---------------------------------------------------------------------------
# Utilities (same patterns as analyzer.py)
# ---------------------------------------------------------------------------
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
    """Safely get a value from a financial statement DataFrame."""
    if df is None or df.empty:
        return None
    for key in keys if isinstance(keys, list) else [keys]:
        if key in df.index:
            try:
                val = df.loc[key].iloc[col]
                if not pd.isna(val):
                    return float(val)
            except (IndexError, KeyError):
                pass
    return None


def calculate_cagr(start_val, end_val, years):
    """CAGR = (end/start)^(1/years) - 1. Returns None if inputs are invalid."""
    if start_val is None or end_val is None or years is None or years <= 0:
        return None
    if start_val <= 0 or end_val <= 0:
        return None
    try:
        return (end_val / start_val) ** (1.0 / years) - 1.0
    except (ZeroDivisionError, ValueError, OverflowError):
        return None


def yoy_growth(current, prior):
    """Calculate year-over-year growth rate."""
    if current is None or prior is None or prior == 0:
        return None
    return (current - prior) / abs(prior)


def get_fiscal_years(df):
    """Extract sorted list of fiscal years from a financial statement DataFrame.

    Returns list of (year_int, col_index) tuples sorted oldest-first.
    """
    if df is None or df.empty:
        return []
    years = []
    for i, col in enumerate(df.columns):
        try:
            yr = col.year
            years.append((yr, i))
        except AttributeError:
            pass
    years.sort(key=lambda x: x[0])
    return years


# ---------------------------------------------------------------------------
# Annual metric extraction — each returns {year: value}
# ---------------------------------------------------------------------------
def extract_annual_roic(fin, bs):
    """Calculate ROIC % for each fiscal year."""
    result = {}
    if fin is None or fin.empty or bs is None or bs.empty:
        return result
    years = get_fiscal_years(fin)
    bs_years = {yr: col for yr, col in get_fiscal_years(bs)}
    for yr, col in years:
        if yr not in bs_years:
            continue
        bs_col = bs_years[yr]
        ebit = get_stmt_value(fin, ["EBIT", "Operating Income"], col=col)
        total_assets = get_stmt_value(bs, ["Total Assets"], col=bs_col)
        cur_liab = get_stmt_value(
            bs, ["Current Liabilities", "Total Current Liabilities"], col=bs_col
        )
        cash = get_stmt_value(
            bs,
            ["Cash And Cash Equivalents", "Cash Cash Equivalents And Short Term Investments"],
            col=bs_col,
        )
        if ebit is not None and total_assets is not None and cur_liab is not None:
            cash = cash or 0
            invested_capital = total_assets - cur_liab - cash
            if invested_capital > 0:
                result[yr] = (ebit / invested_capital) * 100
    return result


def extract_bvps(bs):
    """Calculate Book Value Per Share for each fiscal year."""
    result = {}
    if bs is None or bs.empty:
        return result
    for yr, col in get_fiscal_years(bs):
        equity = get_stmt_value(
            bs,
            ["Stockholders Equity", "Total Equity Gross Minority Interest", "Common Stock Equity"],
            col=col,
        )
        shares = get_stmt_value(
            bs, ["Ordinary Shares Number", "Share Issued"], col=col
        )
        if equity is not None and shares is not None and shares > 0:
            result[yr] = equity / shares
    return result


def extract_eps(fin, bs):
    """Extract Earnings Per Share for each fiscal year."""
    result = {}
    if fin is None or fin.empty:
        return result
    for yr, col in get_fiscal_years(fin):
        eps = get_stmt_value(fin, ["Basic EPS", "Diluted EPS"], col=col)
        if eps is not None:
            result[yr] = eps
        else:
            # Fallback: Net Income / Shares Outstanding
            ni = get_stmt_value(fin, ["Net Income"], col=col)
            if ni is not None and bs is not None:
                bs_years = {y: c for y, c in get_fiscal_years(bs)}
                if yr in bs_years:
                    shares = get_stmt_value(
                        bs, ["Ordinary Shares Number", "Share Issued"],
                        col=bs_years[yr],
                    )
                    if shares is not None and shares > 0:
                        result[yr] = ni / shares
    return result


def extract_revenue(fin):
    """Extract Revenue in millions for each fiscal year."""
    result = {}
    if fin is None or fin.empty:
        return result
    for yr, col in get_fiscal_years(fin):
        rev = get_stmt_value(fin, ["Total Revenue"], col=col)
        if rev is not None:
            result[yr] = rev / 1_000_000
    return result


def extract_fcf(cf):
    """Extract Free Cash Flow in millions for each fiscal year."""
    result = {}
    if cf is None or cf.empty:
        return result
    for yr, col in get_fiscal_years(cf):
        fcf = get_stmt_value(cf, ["Free Cash Flow"], col=col)
        if fcf is not None:
            result[yr] = fcf / 1_000_000
    return result


def extract_avg_prices(ticker_obj, years):
    """Get average share price per year from historical daily data."""
    result = {}
    if not years:
        return result
    try:
        hist = ticker_obj.history(period="5y")
        if hist is None or hist.empty:
            return result
        hist_by_year = hist.groupby(hist.index.year)["Close"].mean()
        for yr in years:
            if yr in hist_by_year.index:
                val = hist_by_year[yr]
                if not pd.isna(val):
                    result[yr] = float(val)
    except Exception as e:
        log.debug(f"  Price history failed: {e}")
    return result


def calculate_avg_pe(avg_prices, eps_by_year):
    """Calculate average PE ratio per year from average price and EPS."""
    result = {}
    for yr in avg_prices:
        price = avg_prices.get(yr)
        eps = eps_by_year.get(yr)
        if price is not None and eps is not None and eps > 0:
            result[yr] = price / eps
    return result


# ---------------------------------------------------------------------------
# TTM and snapshot extraction
# ---------------------------------------------------------------------------
def extract_ttm_values(ticker_obj, info):
    """Extract trailing-twelve-month values from ticker.info."""
    # ROIC TTM: calculate from most recent data
    roic_ttm = None
    try:
        fin = ticker_obj.financials
        bs = ticker_obj.balance_sheet
        if fin is not None and not fin.empty and bs is not None and not bs.empty:
            ebit = get_stmt_value(fin, ["EBIT", "Operating Income"], col=0)
            ta = get_stmt_value(bs, ["Total Assets"], col=0)
            cl = get_stmt_value(bs, ["Current Liabilities", "Total Current Liabilities"], col=0)
            cash = get_stmt_value(
                bs,
                ["Cash And Cash Equivalents", "Cash Cash Equivalents And Short Term Investments"],
                col=0,
            )
            if ebit is not None and ta is not None and cl is not None:
                cash = cash or 0
                ic = ta - cl - cash
                if ic > 0:
                    roic_ttm = (ebit / ic) * 100
    except Exception:
        pass
    if roic_ttm is None:
        roe = info.get("returnOnEquity")
        if roe is not None:
            roic_ttm = safe(roe)
            if roic_ttm is not None:
                roic_ttm *= 100

    bvps_ttm = safe(info.get("bookValue"))
    eps_ttm = safe(info.get("trailingEps"))

    total_rev = safe(info.get("totalRevenue"))
    revenue_ttm = total_rev / 1_000_000 if total_rev is not None else None

    fcf_raw = safe(info.get("freeCashflow"))
    fcf_ttm = fcf_raw / 1_000_000 if fcf_raw is not None else None

    price = safe(info.get("currentPrice")) or safe(info.get("regularMarketPrice"))
    pe_ttm = safe(info.get("trailingPE"))

    return {
        "roic_ttm": roic_ttm,
        "bvps_ttm": bvps_ttm,
        "eps_ttm": eps_ttm,
        "revenue_ttm_mil": revenue_ttm,
        "fcf_ttm_mil": fcf_ttm,
        "price_current": price,
        "pe_ttm": pe_ttm,
    }


def extract_snapshot(ticker_obj, info, bs):
    """Extract point-in-time snapshot metrics."""
    roa = safe(info.get("returnOnAssets"))
    roa_pct = roa * 100 if roa is not None else None

    roe = safe(info.get("returnOnEquity"))
    roe_pct = roe * 100 if roe is not None else None

    # Dividends: prefer dividendRate, fallback to summing last 12 months
    dividends_ttm = safe(info.get("dividendRate"))
    if dividends_ttm is None:
        try:
            divs = ticker_obj.dividends
            if divs is not None and not divs.empty:
                one_year_ago = pd.Timestamp.now(tz=divs.index.tz) - pd.DateOffset(years=1)
                dividends_ttm = float(divs[divs.index >= one_year_ago].sum())
                if dividends_ttm == 0:
                    dividends_ttm = None
        except Exception:
            pass

    div_yield = safe(info.get("dividendYield"))
    div_yield_pct = div_yield * 100 if div_yield is not None else None

    # Total liabilities from balance sheet
    total_liab = None
    if bs is not None and not bs.empty:
        total_liab = get_stmt_value(
            bs, ["Total Liabilities Net Minority Interest", "Total Liab"], col=0
        )

    debt_to_equity = safe(info.get("debtToEquity"))
    current_ratio = safe(info.get("currentRatio"))

    # Quick ratio: (Current Assets - Inventory) / Current Liabilities
    quick_ratio = None
    if bs is not None and not bs.empty:
        ca = get_stmt_value(bs, ["Current Assets", "Total Current Assets"], col=0)
        inv = get_stmt_value(bs, ["Inventory"]) or 0
        cl = get_stmt_value(
            bs, ["Current Liabilities", "Total Current Liabilities"], col=0
        )
        if ca is not None and cl is not None and cl > 0:
            quick_ratio = (ca - inv) / cl

    return {
        "roa_pct": roa_pct,
        "roe_pct": roe_pct,
        "dividends_ttm": dividends_ttm,
        "dividend_yield_pct": div_yield_pct,
        "total_liabilities": total_liab,
        "debt_to_equity": debt_to_equity,
        "current_ratio": current_ratio,
        "quick_ratio": quick_ratio,
    }


# ---------------------------------------------------------------------------
# Process a single ticker
# ---------------------------------------------------------------------------
def process_ticker(symbol):
    """Fetch data and calculate all Rule #1 metrics for one ticker.

    Returns (annual_rows, summary_row) or (None, None) on failure.
    """
    t = yf.Ticker(symbol)
    info = t.info

    if not info or info.get("regularMarketPrice") is None:
        log.warning(f"  {symbol}: no data available, skipping")
        return None, None

    fin = t.financials
    bs = t.balance_sheet
    cf = t.cashflow

    # Extract annual values (dicts keyed by fiscal year)
    roic_by_year = extract_annual_roic(fin, bs)
    bvps_by_year = extract_bvps(bs)
    eps_by_year = extract_eps(fin, bs)
    rev_by_year = extract_revenue(fin)
    fcf_by_year = extract_fcf(cf)

    # Collect all fiscal years we have data for
    all_years = sorted(set(
        list(roic_by_year.keys()) + list(bvps_by_year.keys()) +
        list(eps_by_year.keys()) + list(rev_by_year.keys()) +
        list(fcf_by_year.keys())
    ))

    if not all_years:
        log.warning(f"  {symbol}: no annual financial data available")
        return None, None

    # Get average prices and PE for those years
    avg_prices = extract_avg_prices(t, all_years)
    avg_pe = calculate_avg_pe(avg_prices, eps_by_year)

    # Build annual rows (oldest first) with YoY growth
    annual_rows = []
    prev = {}
    for yr in all_years:
        row = {
            "fiscal_year": yr,
            "roic_pct": roic_by_year.get(yr),
            "book_value_per_share": bvps_by_year.get(yr),
            "earnings_per_share": eps_by_year.get(yr),
            "revenue_mil": rev_by_year.get(yr),
            "fcf_mil": fcf_by_year.get(yr),
            "avg_share_price": avg_prices.get(yr),
            "avg_pe": avg_pe.get(yr),
        }

        # YoY growth for each metric
        yoy_pairs = [
            ("roic_pct", "roic_yoy"),
            ("book_value_per_share", "bvps_yoy"),
            ("earnings_per_share", "eps_yoy"),
            ("revenue_mil", "revenue_yoy"),
            ("fcf_mil", "fcf_yoy"),
            ("avg_share_price", "price_yoy"),
            ("avg_pe", "pe_yoy"),
        ]
        for raw_key, yoy_key in yoy_pairs:
            row[yoy_key] = yoy_growth(row[raw_key], prev.get(raw_key))

        prev = {k: row[k] for k, _ in yoy_pairs}
        annual_rows.append(row)

    # TTM and snapshot
    ttm = extract_ttm_values(t, info)
    snapshot = extract_snapshot(t, info, bs)

    # CAGRs
    earliest = annual_rows[0]
    latest = annual_rows[-1]
    years_full = latest["fiscal_year"] - earliest["fiscal_year"]

    # Second-to-last annual row for recent CAGR
    second_to_last = annual_rows[-2] if len(annual_rows) >= 2 else {}
    years_recent = date.today().year - second_to_last.get("fiscal_year", date.today().year)
    if years_recent <= 0:
        years_recent = None

    # Build CAGR mappings: (annual_key, ttm_key, cagr_full_key, cagr_recent_key)
    cagr_map = [
        ("roic_pct", "roic_ttm", "roic_cagr_full", "roic_cagr_recent"),
        ("book_value_per_share", "bvps_ttm", "bvps_cagr_full", "bvps_cagr_recent"),
        ("earnings_per_share", "eps_ttm", "eps_cagr_full", "eps_cagr_recent"),
        ("revenue_mil", "revenue_ttm_mil", "revenue_cagr_full", "revenue_cagr_recent"),
        ("fcf_mil", "fcf_ttm_mil", "fcf_cagr_full", "fcf_cagr_recent"),
        ("avg_share_price", "price_current", "price_cagr_full", "price_cagr_recent"),
        ("avg_pe", "pe_ttm", "pe_cagr_full", "pe_cagr_recent"),
    ]

    summary = {
        "years_of_data": len(all_years),
    }
    for annual_key, ttm_key, full_key, recent_key in cagr_map:
        summary[full_key] = calculate_cagr(
            earliest.get(annual_key), latest.get(annual_key), years_full
        )
        summary[recent_key] = calculate_cagr(
            second_to_last.get(annual_key), ttm.get(ttm_key), years_recent
        )

    summary.update(ttm)
    summary.update(snapshot)

    return annual_rows, summary


# ---------------------------------------------------------------------------
# Database operations
# ---------------------------------------------------------------------------
def upsert_annual(engine, ticker, annual_rows):
    """Insert or update annual metrics rows."""
    cols = [
        "roic_pct", "book_value_per_share", "earnings_per_share",
        "revenue_mil", "fcf_mil", "avg_share_price", "avg_pe",
        "roic_yoy", "bvps_yoy", "eps_yoy", "revenue_yoy",
        "fcf_yoy", "price_yoy", "pe_yoy",
    ]
    col_list = ", ".join(cols)
    val_list = ", ".join(f":{c}" for c in cols)
    update_list = ", ".join(f"{c} = EXCLUDED.{c}" for c in cols)

    with engine.begin() as conn:
        for row in annual_rows:
            params = {"ticker": ticker, "fiscal_year": row["fiscal_year"]}
            for c in cols:
                params[c] = row.get(c)
            conn.execute(
                text(f"""
                    INSERT INTO rule1_annual (ticker, fiscal_year, {col_list}, updated_at)
                    VALUES (:ticker, :fiscal_year, {val_list}, NOW())
                    ON CONFLICT (ticker, fiscal_year) DO UPDATE SET
                        {update_list}, updated_at = NOW()
                """),
                params,
            )


def upsert_summary(engine, ticker, summary):
    """Insert or update summary metrics for today."""
    today = date.today()
    cols = [
        "years_of_data",
        "roic_cagr_full", "bvps_cagr_full", "eps_cagr_full",
        "revenue_cagr_full", "fcf_cagr_full", "price_cagr_full", "pe_cagr_full",
        "roic_cagr_recent", "bvps_cagr_recent", "eps_cagr_recent",
        "revenue_cagr_recent", "fcf_cagr_recent", "price_cagr_recent", "pe_cagr_recent",
        "roic_ttm", "bvps_ttm", "eps_ttm", "revenue_ttm_mil",
        "fcf_ttm_mil", "price_current", "pe_ttm",
        "roa_pct", "roe_pct", "dividends_ttm", "dividend_yield_pct",
        "total_liabilities", "debt_to_equity", "current_ratio", "quick_ratio",
    ]
    col_list = ", ".join(cols)
    val_list = ", ".join(f":{c}" for c in cols)
    update_list = ", ".join(f"{c} = EXCLUDED.{c}" for c in cols)

    params = {"ticker": ticker, "calc_date": today}
    for c in cols:
        params[c] = summary.get(c)

    with engine.begin() as conn:
        conn.execute(
            text(f"""
                INSERT INTO rule1_summary (ticker, calc_date, {col_list}, updated_at)
                VALUES (:ticker, :calc_date, {val_list}, NOW())
                ON CONFLICT (ticker, calc_date) DO UPDATE SET
                    {update_list}, updated_at = NOW()
            """),
            params,
        )


# ---------------------------------------------------------------------------
# Summary report
# ---------------------------------------------------------------------------
def print_rule1_report(engine):
    """Print a summary of Rule #1 metrics for all tickers."""
    today = date.today()
    df = pd.read_sql(
        text("""
            SELECT ticker, years_of_data,
                   bvps_cagr_full, eps_cagr_full, revenue_cagr_full, fcf_cagr_full,
                   roic_ttm, roe_pct, debt_to_equity, current_ratio, quick_ratio
            FROM rule1_summary
            WHERE calc_date = :today
            ORDER BY eps_cagr_full DESC NULLS LAST
        """),
        engine,
        params={"today": today},
    )
    if df.empty:
        log.info("No Rule #1 summary data for today.")
        return

    # Format percentages
    pct_cols = ["bvps_cagr_full", "eps_cagr_full", "revenue_cagr_full", "fcf_cagr_full", "roic_ttm", "roe_pct"]
    for col in pct_cols:
        if col in df.columns:
            df[col] = df[col].apply(lambda x: f"{x:.1f}%" if pd.notna(x) else "N/A")

    for col in ["debt_to_equity", "current_ratio", "quick_ratio"]:
        if col in df.columns:
            df[col] = df[col].apply(lambda x: f"{x:.2f}" if pd.notna(x) else "N/A")

    log.info(f"\n{'='*80}")
    log.info("Rule #1 Summary — Phil Town Metrics")
    log.info(f"{'='*80}")
    log.info(f"\n{df.to_string(index=False)}")

    # Count tickers meeting Rule #1 criteria (all CAGRs > 10%)
    numeric_df = pd.read_sql(
        text("""
            SELECT ticker,
                   bvps_cagr_full, eps_cagr_full, revenue_cagr_full, fcf_cagr_full
            FROM rule1_summary
            WHERE calc_date = :today
        """),
        engine,
        params={"today": today},
    )
    if not numeric_df.empty:
        cagr_cols = ["bvps_cagr_full", "eps_cagr_full", "revenue_cagr_full", "fcf_cagr_full"]
        passing = numeric_df.dropna(subset=cagr_cols)
        if not passing.empty:
            rule1_pass = passing[
                (passing["bvps_cagr_full"] >= 10) &
                (passing["eps_cagr_full"] >= 10) &
                (passing["revenue_cagr_full"] >= 10) &
                (passing["fcf_cagr_full"] >= 10)
            ]
            log.info(f"\nRule #1 Pass (all CAGRs >= 10%): {len(rule1_pass)} of {len(numeric_df)} tickers")
            if not rule1_pass.empty:
                log.info(f"  Tickers: {', '.join(rule1_pass['ticker'].tolist())}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    log.info("Rule #1 Analyzer starting...")

    engine = create_engine(DATABASE_URL)
    create_tables(engine)

    tickers = get_tickers()
    log.info(f"Processing {len(tickers)} tickers...")

    success = 0
    errors = 0

    for i, symbol in enumerate(tickers, 1):
        try:
            log.info(f"[{i}/{len(tickers)}] {symbol}")
            annual_rows, summary = process_ticker(symbol)

            if annual_rows is not None:
                upsert_annual(engine, symbol, annual_rows)
                upsert_summary(engine, symbol, summary)
                yrs = len(annual_rows)
                bvps_cagr = summary.get("bvps_cagr_full")
                eps_cagr = summary.get("eps_cagr_full")
                bvps_str = f"{bvps_cagr:.1%}" if bvps_cagr is not None else "N/A"
                eps_str = f"{eps_cagr:.1%}" if eps_cagr is not None else "N/A"
                log.info(f"  -> {yrs} years, BVPS CAGR: {bvps_str}, EPS CAGR: {eps_str}")
                success += 1
            else:
                errors += 1

            if i < len(tickers):
                time.sleep(DELAY)

        except Exception as e:
            log.error(f"  Error: {e}")
            errors += 1

    log.info(f"\nFetch complete: {success} ok, {errors} failed")

    log.info("Generating Rule #1 report...")
    print_rule1_report(engine)

    log.info("Rule #1 Analyzer finished!")


if __name__ == "__main__":
    main()
