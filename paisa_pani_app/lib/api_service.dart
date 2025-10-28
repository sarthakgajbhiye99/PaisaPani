import 'dart:convert';
import 'package:http/http.dart' as http;
import 'main.dart'; // Import your main file to get the Expense class

class ApiService {
  // IMPORTANT: Use 10.0.2.2 for Android Emulator to connect to your PC's localhost
  // If using a physical device, find your computer's IP address and use that.
  final String _baseUrl = "http://10.0.2.2:8000";

  /// Aggregates expenses into a list of monthly totals,
  /// matching what the Python API expects.
  Map<String, dynamic> _aggregateMonthly(List<Expense> expenses) {
    if (expenses.isEmpty) {
      return {"monthly_amounts": [], "last_month_iso": ""};
    }

    // Filter for expenses only
    final expenseList = expenses
        .where((exp) => exp.transactionType == 'Debit')
        .toList();
    if (expenseList.isEmpty) {
      return {"monthly_amounts": [], "last_month_iso": ""};
    }
    
    // Sort by date just in case
    expenseList.sort((a, b) => a.date.compareTo(b.date));

    Map<DateTime, double> monthlyTotals = {};
    
    // Sum expenses for each month
    for (final exp in expenseList) {
      final monthKey = DateTime(exp.date.year, exp.date.month, 1);
      monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + exp.amount;
    }
    
    // Get date range
    final sortedMonthKeys = monthlyTotals.keys.toList()..sort();
    final firstMonth = sortedMonthKeys.first;
    final lastMonth = sortedMonthKeys.last;

    List<double> monthlyAmounts = [];
    DateTime currentMonth = firstMonth;

    // Fill in 0s for months with no spending to create a continuous list
    while (currentMonth.isBefore(lastMonth) || currentMonth.isAtSameMomentAs(lastMonth)) {
      monthlyAmounts.add(monthlyTotals[currentMonth] ?? 0.0);
      // Move to the next month
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
    }
    
    return {
      "monthly_amounts": monthlyAmounts,
      "last_month_iso": lastMonth.toIso8601String()
    };
  }

  /// Fetches the 3-month forecast from the Python API
  Future<List<Map<String, dynamic>>> getForecast(List<Expense> allExpenses) async {
    try {
      // 1. Aggregate expenses into the format the API needs
      final Map<String, dynamic> apiPayload = _aggregateMonthly(allExpenses);

      if ((apiPayload["monthly_amounts"] as List).isEmpty) {
        return []; // Not enough data, return empty list
      }

      // 2. Send to API
      final response = await http.post(
        Uri.parse("$_baseUrl/forecast/monthly"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(apiPayload),
      );

      if (response.statusCode == 200) {
        // 3. Parse and return the raw forecast list
        final data = jsonDecode(response.body);
        
        // The API returns [{"month": "2025-11-01", "predicted_expense": 12345.67}, ...]
        // We will return this directly.
        final List<Map<String, dynamic>> forecast = List<Map<String, dynamic>>.from(data['forecast']);
        return forecast;

      } else {
        print("API Error: ${response.statusCode} ${response.body}");
        throw Exception("Failed to get forecast from API (${response.statusCode})");
      }
    } catch (e) {
      print("Error calling forecast API: $e");
      return [];
    }
  }}