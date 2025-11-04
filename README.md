# 💰 Paisa Pani: Predictive Finance Manager

Paisa Pani is a cross-platform mobile application designed to simplify personal expense tracking and provide forward-looking budget forecasts using local machine learning integration. Built with Flutter, it utilizes a dedicated Python backend to analyze monthly spending trends and predict future expenses.

<img width="416" height="920" alt="image" src="https://github.com/user-attachments/assets/63483aa2-7811-40bb-a5f4-df4ac764701b" />


---

## ✨ Features

* **Intelligent Data Entry:** Capture transactions via three methods:
    1.  **Manual Entry:** Standard form for adding expenses or income.
    2.  **SMS Import:** Scans the user's SMS inbox to parse and import bank debit transactions.
    3.  **Receipt Scanner (OCR):** Uses Google ML Kit to scan receipts, automatically extracting the vendor, amount, and date.
* **Predictive Forecasting:** Communicates with a Python/FastAPI server to retrieve a **3-month spending forecast** based on the user's historical monthly expense data.
* **Persistent Storage:** All user-generated transactions and income settings are stored locally on the device using the **Hive NoSQL database**.
* **Real-time Reporting:**
    * **Dashboard:** An at-a-glance view of total income, expenses, and net balance.
    * **Monthly Reports:** An interactive pie chart showing spending distribution by category for any given month.
    * **Forecast Page:** A line chart visualizing historical spending vs. the model's prediction.
* **Reactive UI:** The app uses a `ValueNotifier` to ensure all screens update instantly when a new transaction is added, edited, or deleted.

---

## 🛠️ Technology Stack

| Component | Technology | Role |
| :--- | :--- | :--- |
| **Frontend (Mobile)** | Flutter / Dart | Cross-platform UI, state management, and native feature access. |
| **Local Database** | Hive (NoSQL) | High-speed, persistent on-device storage for all user transactions. |
| **Text Recognition** | Google ML Kit (OCR) | Extracts text from receipt images in a background isolate. |
| **SMS Reading** | `another_telephony` | Reads the native Android SMS inbox for transaction parsing. |
| **Charting** | `fl_chart` | Creates interactive pie and line charts for reports and forecasts. |
| **Backend API** | FastAPI (Python) | Serves the ML model as a high-performance RESTful API. |
| **Machine Learning** | Scikit-learn, Pandas | Trains a `RandomForestRegressor` on time-series features. |
| **Model Serving** | `joblib` | Serializes (saves) the trained Python model for the API to use. |

---

## 🚀 Setup and Installation

This project consists of two parts: the Flutter application and the Python backend API.

### 1. Flutter Application Setup

1.  Clone the repository:
    ```bash
    git clone https://github.com/sarthakgajbhiye99/PaisaPani
    cd paisa-pani-app
    ```
2.  Install Flutter dependencies:
    ```bash
    flutter pub get
    ```
3.  Generate Hive Adapters (Required):
    ```bash
    flutter pub run build_runner build --delete-conflicting-outputs
    ```

### 2. Python Backend Setup

The backend server is located in the `lib/backend` directory.

1.  Navigate to the backend directory:
    ```bash
    cd lib/backend
    ```
2.  Create and activate a Python virtual environment:
    ```bash
    # Create the environment
    python -m venv .venv
    
    # Activate (Windows)
    .venv\Scripts\activate
    
    # Activate (macOS/Linux)
    # source .venv/bin/activate
    ```
3.  Install Python dependencies:
    ```bash
    pip install -r requirements.txt
    ```
4.  **Train the Model:**
    You must run the training script once to create the `budget_forecast_model.joblib` file. This script requires a CSV of sample data (a placeholder `indian_expense_data.csv` is expected).
    ```bash
    python train_model.py
    ```

### 5. Running the Full System

1.  **Start the Backend:** In one terminal (inside `lib/backend`), run the FastAPI server:
    ```bash
    uvicorn main:app --reload
    ```
    The API will be live at `http://127.0.0.1:8000`.

2.  **Start the App:** In a second terminal (at the project root), run the Flutter app:
    ```bash
    flutter run
    ```
    The app is pre-configured to connect to `http://10.0.2.2:8000`, which is the special address for the Android Emulator to access your computer's `localhost`.


### App Screenshots

<img width="412" height="914" alt="image" src="https://github.com/user-attachments/assets/7ca2e374-bd56-4818-a6f3-c51ce90c2890" />
<img width="408" height="951" alt="image" src="https://github.com/user-attachments/assets/bfc9f559-28b7-4b84-8f05-2357af44d69e" />
<img width="408" height="917" alt="image" src="https://github.com/user-attachments/assets/a3f10733-3a2e-4c23-97c3-95e62dd882eb" />
<img width="410" height="912" alt="image" src="https://github.com/user-attachments/assets/74852c39-291d-4334-b39d-77f1bc59e546" />






