from fastapi import FastAPI
from pydantic import BaseModel
import joblib
import pandas as pd
import numpy as np
import os

app = FastAPI(title="Budget Forecast API")

# --- 1. Load Model ---
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
MODEL_PATH = os.path.join(SCRIPT_DIR, "budget_forecast_model.joblib")

try:
    model_data = joblib.load(MODEL_PATH)
    model = model_data['model']
    FEATURES = model_data['features'] # ['month_num', 'year', 'lag_1', 'lag_2', 'lag_3', 'rolling_3']
except FileNotFoundError:
    print(f"ERROR: Model file not found at {MODEL_PATH}")
    print("Please run train_model.py first to create 'budget_forecast_model.joblib'")
    model = None
    FEATURES = []

# --- 2. Pydantic Models ---
class ForecastRequest(BaseModel):
    # The Flutter app will send its historical data aggregated by month
    monthly_amounts: list[float] 
    # It also sends the *last month* it has data for, as an ISO string
    last_month_iso: str # e.g., "2025-10-01"

class ForecastResponse(BaseModel):
    forecast: list[dict] # e.g., [{"month": "2025-11-01", "amount": 15000.50}, ...]

# --- 3. API Endpoint ---
@app.post("/forecast/monthly", response_model=ForecastResponse)
async def get_monthly_forecast(data: ForecastRequest):

    if not model:
         return {"forecast": [{"error": "Model not loaded. Check server logs."}]}

    # We need at least 3 months of history for our features (lag_3)
    if len(data.monthly_amounts) < 3:
        # Not enough data to use the model, return an empty forecast
        return {"forecast": []} 

    # Create a DataFrame from the history to easily calculate features
    # This logic exactly mirrors STEP 9 from your training script
    last_known_date = pd.to_datetime(data.last_month_iso)
    history_dates = pd.date_range(end=last_known_date, periods=len(data.monthly_amounts), freq='MS')

    last_data = pd.DataFrame({
        'month': history_dates,
        'amount': data.monthly_amounts
    })

    future_predictions = []
    future_months = pd.date_range(
        start=last_known_date + pd.offsets.MonthBegin(1),
        periods=3, freq='MS' # Forecast 3 months
    )

    for m in future_months:
        last_3 = last_data['amount'].iloc[-3:] # Get last 3 known amounts
        features = {
            'month_num': m.month,
            'year': m.year,
            'lag_1': last_3.iloc[-1],
            'lag_2': last_3.iloc[-2],
            'lag_3': last_3.iloc[-3],
            'rolling_3': last_3.mean()
        }
        # Ensure column order matches the model's training
        X_future = pd.DataFrame([features])[FEATURES] 

        pred = model.predict(X_future)[0]
        pred = max(0, pred) # Don't forecast negative spending

        future_predictions.append({'month': m.strftime('%Y-%m-%d'), 'predicted_expense': round(pred, 2)})

        # Append this new prediction to last_data for the next loop (auto-regressive)
        last_data = pd.concat([
            last_data,
            pd.DataFrame({'month': [m], 'amount': [pred]})
        ], ignore_index=True)

    return {"forecast": future_predictions}