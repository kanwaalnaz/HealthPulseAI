from pathlib import Path

import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report
from sklearn.model_selection import train_test_split

# ==========================================================
# HealthPulseAI - Machine Learning
# ==========================================================

BASE_DIR = Path(__file__).resolve().parent
RAW_DATA = BASE_DIR / "data" / "raw"

# ----------------------------------------------------------
# Load Dataset
# ----------------------------------------------------------

df = pd.read_csv(RAW_DATA / "ai_predictions.csv")

print("=" * 70)
print("HealthPulseAI Machine Learning")
print("=" * 70)

print("\nDataset Shape:")
print(df.shape)

print("\nColumns:")
print(df.columns.tolist())

# ----------------------------------------------------------
# Target Column
# ----------------------------------------------------------

target = "PredictedClass"

if target not in df.columns:
    print(f"\nTarget column '{target}' not found.")
    exit()

# ----------------------------------------------------------
# Feature Selection
# ----------------------------------------------------------

X = df.drop(columns=[target])

# Remove IDs
columns_to_remove = [
    "PredictionID",
    "ModelVersionID",
    "PatientID",
    "EncounterID",
]

X = X.drop(
    columns=[col for col in columns_to_remove if col in X.columns]
)

# Keep only useful numeric features
numeric_features = [
    "PredictedValue",
    "ProbabilityScore",
    "RiskScore",
    "ThresholdUsed",
]

X = X[[col for col in numeric_features if col in X.columns]]

# Convert to numeric
for column in X.columns:
    X[column] = pd.to_numeric(X[column], errors="coerce")

# Fill missing values
X = X.fillna(X.median())

# ----------------------------------------------------------
# Target Variable
# ----------------------------------------------------------

y = df[target].astype(str)

valid_rows = df[target].notna()

X = X.loc[valid_rows]
y = y.loc[valid_rows]

print("\nFeatures Used:")
print(X.columns.tolist())

print("\nTarget Classes:")
print(y.value_counts())

# ----------------------------------------------------------
# Train/Test Split
# ----------------------------------------------------------

X_train, X_test, y_train, y_test = train_test_split(
    X,
    y,
    test_size=0.20,
    random_state=42,
    stratify=y,
)

# ----------------------------------------------------------
# Model
# ----------------------------------------------------------

model = RandomForestClassifier(
    n_estimators=100,
    random_state=42,
)

model.fit(X_train, y_train)

# ----------------------------------------------------------
# Prediction
# ----------------------------------------------------------

predictions = model.predict(X_test)

accuracy = accuracy_score(y_test, predictions)

print("\n" + "=" * 70)
print("Model Accuracy")
print("=" * 70)

print(f"Accuracy: {accuracy:.2%}")

print("\nClassification Report")
print("=" * 70)

print(classification_report(y_test, predictions, zero_division=0))

# ----------------------------------------------------------
# Feature Importance
# ----------------------------------------------------------

importance = pd.DataFrame(
    {
        "Feature": X.columns,
        "Importance": model.feature_importances_,
    }
)

importance = importance.sort_values(
    by="Importance",
    ascending=False,
)

print("\nFeature Importance")
print("=" * 70)

print(importance.to_string(index=False))

print("\nMachine Learning Pipeline Completed Successfully!")