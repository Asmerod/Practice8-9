"""Reproduce EUR/USD New York 17:00 daily candles from Dukascopy H1 Bid CSV.
Run: python prepare_eurusd.py --input eurusd-h1-bid-2025-10-01-2026-10-01.csv --output reproduced.csv
Requires pandas and tzdata (on Windows): pip install pandas tzdata
"""

import argparse
import pandas as pd

def build(source):
    x = pd.read_csv(source)
    required = ['timestamp', 'open', 'high', 'low', 'close']
    if list(x.columns) != required:
        raise ValueError(f'Expected columns {required}, found {list(x.columns)}')
    if x[required].isna().any().any() or x.timestamp.duplicated().any():
        raise ValueError('Missing values or duplicate timestamps')
    if not ((x.high >= x[['open','close','low']].max(axis=1)) & (x.low <= x[['open','close','high']].min(axis=1))).all():
        raise ValueError('Invalid source OHLC')
    x = x.sort_values('timestamp').copy()
    ny = pd.to_datetime(x.timestamp, unit='ms', utc=True).dt.tz_convert('America/New_York')
    # H1 timestamps are the beginning of their one-hour intervals.
    # NY trading day ends at 17:00 local: intervals starting 17:00 belong to next date.
    trading_date = (ny.dt.tz_localize(None) + pd.to_timedelta((ny.dt.hour >= 17).astype(int), unit='D')).dt.normalize()
    x['date'] = trading_date
    x = x[x.date.dt.dayofweek < 5]
    out = x.groupby('date', sort=True).agg(open=('open','first'), high=('high','max'), low=('low','min'), close=('close','last'), hourly_bars=('close','size')).reset_index()
    out['quality_flag'] = out.hourly_bars.map(lambda n: 'complete' if n == 24 else 'missing_hourly_bars')
    # Preserve the decision log's inclusion rule: full sessions only, omit 2026-01-01.
    out = out[(out.hourly_bars == 24) & (out.date != pd.Timestamp('2026-01-01'))].copy()
    out['date'] = out.date.dt.strftime('%Y-%m-%d')
    return out.reset_index(drop=True)

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--input', default='eurusd-h1-bid-2025-10-01-2026-10-01.csv')
    p.add_argument('--output', default='EURUSD_D1_reproduced.csv')
    args = p.parse_args()
    result = build(args.input)
    result.to_csv(args.output, index=False, float_format='%.5f')
    print(f'Saved {len(result)} rows to {args.output}; range {result.date.iloc[0]} to {result.date.iloc[-1]}')
