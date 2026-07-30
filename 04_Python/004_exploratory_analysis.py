from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


BASE_DIR = Path(__file__).resolve().parent
RAW_DATA_DIR = BASE_DIR / "data" / "raw"
CHARTS_DIR = BASE_DIR / "outputs" / "charts"
REPORTS_DIR = BASE_DIR / "outputs" / "reports"


def load_dataset(name: str) -> pd.DataFrame:
    """Load one extracted CSV dataset."""

    file_path = RAW_DATA_DIR / f"{name}.csv"

    if not file_path.exists():
        raise FileNotFoundError(f"Dataset not found: {file_path}")

    return pd.read_csv(file_path)


def create_dataset_summary() -> pd.DataFrame:
    """Create a high-level summary of all raw datasets."""

    summary_rows = []

    for file_path in sorted(RAW_DATA_DIR.glob("*.csv")):
        dataframe = pd.read_csv(file_path)

        summary_rows.append(
            {
                "dataset": file_path.stem,
                "rows": len(dataframe),
                "columns": len(dataframe.columns),
                "missing_values": int(dataframe.isna().sum().sum()),
                "duplicate_rows": int(dataframe.duplicated().sum()),
            }
        )

    return pd.DataFrame(summary_rows)


def create_row_count_chart(summary: pd.DataFrame) -> None:
    """Create a bar chart showing row counts by dataset."""

    plt.figure(figsize=(10, 6))
    plt.bar(summary["dataset"], summary["rows"])
    plt.title("HealthPulseAI Dataset Row Counts")
    plt.xlabel("Dataset")
    plt.ylabel("Number of Rows")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()

    output_path = CHARTS_DIR / "dataset_row_counts.png"
    plt.savefig(output_path, dpi=300)
    plt.close()


def create_missing_values_chart(summary: pd.DataFrame) -> None:
    """Create a bar chart showing missing values by dataset."""

    plt.figure(figsize=(10, 6))
    plt.bar(summary["dataset"], summary["missing_values"])
    plt.title("Missing Values by Dataset")
    plt.xlabel("Dataset")
    plt.ylabel("Missing Values")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()

    output_path = CHARTS_DIR / "missing_values_by_dataset.png"
    plt.savefig(output_path, dpi=300)
    plt.close()


def run_eda() -> None:
    """Run the first HealthPulseAI exploratory analysis."""

    CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    summary = create_dataset_summary()

    report_path = REPORTS_DIR / "eda_dataset_summary.csv"
    summary.to_csv(report_path, index=False)

    create_row_count_chart(summary)
    create_missing_values_chart(summary)

    print("=" * 80)
    print("HealthPulseAI Exploratory Data Analysis")
    print("=" * 80)
    print(summary.to_string(index=False))
    print("=" * 80)
    print(f"Summary report saved to: {report_path}")
    print(f"Charts saved to: {CHARTS_DIR}")
    print("=" * 80)


if __name__ == "__main__":
    run_eda()