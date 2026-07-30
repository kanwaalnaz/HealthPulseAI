from __future__ import annotations

from pathlib import Path

import pandas as pd


BASE_DIR = Path(__file__).resolve().parent
RAW_DATA_DIR = BASE_DIR / "data" / "raw"
REPORTS_DIR = BASE_DIR / "outputs" / "reports"


def validate_dataset(file_path: Path) -> dict:
    """Validate one CSV dataset and return summary metrics."""

    dataframe = pd.read_csv(file_path)

    duplicate_rows = int(dataframe.duplicated().sum())
    total_missing_values = int(dataframe.isna().sum().sum())

    empty_columns = [
        column
        for column in dataframe.columns
        if dataframe[column].isna().all()
    ]

    return {
        "dataset": file_path.stem,
        "rows": len(dataframe),
        "columns": len(dataframe.columns),
        "duplicate_rows": duplicate_rows,
        "missing_values": total_missing_values,
        "empty_columns": ", ".join(empty_columns) if empty_columns else "None",
    }


def run_validation() -> None:
    """Validate all extracted CSV files and create a report."""

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    csv_files = sorted(RAW_DATA_DIR.glob("*.csv"))

    if not csv_files:
        print("No CSV files found in data/raw.")
        return

    validation_results = []

    print("=" * 90)
    print("HealthPulseAI Data Validation Report")
    print("=" * 90)

    for file_path in csv_files:
        result = validate_dataset(file_path)
        validation_results.append(result)

        print(f"Dataset:         {result['dataset']}")
        print(f"Rows:            {result['rows']}")
        print(f"Columns:         {result['columns']}")
        print(f"Duplicate rows:  {result['duplicate_rows']}")
        print(f"Missing values:  {result['missing_values']}")
        print(f"Empty columns:   {result['empty_columns']}")
        print("-" * 90)

    report_dataframe = pd.DataFrame(validation_results)

    report_path = REPORTS_DIR / "data_validation_summary.csv"
    report_dataframe.to_csv(report_path, index=False)

    print("=" * 90)
    print(f"Validation completed. Report saved to:")
    print(report_path)
    print("=" * 90)


if __name__ == "__main__":
    run_validation()