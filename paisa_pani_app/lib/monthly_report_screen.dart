import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'main.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  late DateTime _selectedDate;
  double _totalIncome = 0.0;
  double _totalExpenses = 0.0;
  double _netBalance = 0.0;

  List<PieChartSectionData> _pieChartSections = [];
  List<MapEntry<String, double>> _categorySpending = [];
  int _touchedIndex = -1;

  final List<Color> _chartColors = [
    Colors.teal.shade400,
    Colors.indigo.shade400,
    Colors.orange.shade400,
    Colors.purple.shade400,
    Colors.pink.shade300,
    Colors.green.shade400,
    Colors.blue.shade400,
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
    ExpenseService.dataChanged.addListener(_processData);
    _processData();
  }

  @override
  void dispose() {
    ExpenseService.dataChanged.removeListener(_processData);
    super.dispose();
  }

  void _processData() {
    final allExpenses = ExpenseService.getExpenses();

    final monthExpenses = allExpenses.where((exp) =>
        exp.date.year == _selectedDate.year &&
        exp.date.month == _selectedDate.month).toList();

    double income = 0.0;
    double expenses = 0.0;
    final Map<String, double> categoryMap = {};

    for (final exp in monthExpenses) {
      if (exp.transactionType == 'Credit') {
        income += exp.amount;
      } else {
        expenses += exp.amount;
        if (exp.category != 'Income') {
          categoryMap[exp.category] =
              (categoryMap[exp.category] ?? 0) + exp.amount;
        }
      }
    }

    final sortedCategories = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final List<PieChartSectionData> pieSections = [];
    int colorIndex = 0;
    for (var entry in sortedCategories) {
      final isTouched = sortedCategories.indexOf(entry) == _touchedIndex;
      final fontSize = isTouched ? 18.0 : 13.0;
      final radius = isTouched ? 65.0 : 55.0;

      pieSections.add(PieChartSectionData(
        color: _chartColors[colorIndex % _chartColors.length],
        value: entry.value,
        title: '${(entry.value / expenses * 100).toStringAsFixed(0)}%',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 2)],
        ),
      ));
      colorIndex++;
    }

    if (mounted) {
      setState(() {
        _totalIncome = income;
        _totalExpenses = expenses;
        _netBalance = income - expenses;
        _categorySpending = sortedCategories;
        _pieChartSections = (expenses > 0) ? pieSections : [];
      });
    }
  }

  void _goToPreviousMonth() {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
    });
    _processData();
  }

  void _goToNextMonth() {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
    });
    _processData();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isNextMonthFuture = _selectedDate.year > now.year ||
        (_selectedDate.year == now.year && _selectedDate.month >= now.month);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Monthly Report", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.teal.shade600,
      ),
      body: Column(
        children: [
          // Month selector
          Container(
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.teal.shade100),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: _goToPreviousMonth),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedDate),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isNextMonthFuture ? null : _goToNextMonth,
                  color: isNextMonthFuture ? Colors.grey : Colors.black,
                ),
              ],
            ),
          ),

          // Stat cards
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _buildStatCard("Income", _totalIncome, Colors.green, Icons.arrow_upward),
                const SizedBox(width: 12),
                _buildStatCard("Expenses", _totalExpenses, Colors.red, Icons.arrow_downward),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildStatCard(
              "Net Balance",
              _netBalance,
              _netBalance >= 0 ? Colors.indigo : Colors.orange,
              Icons.account_balance_wallet,
              isFullWidth: true,
            ),
          ),
          const Divider(height: 24),

          Expanded(
            child: _totalExpenses == 0
                ? const Center(
                    child: Text(
                      "No expenses recorded for this month.",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      // Pie chart
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              const Text("Spending Breakdown",
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 220,
                                child: PieChart(
                                  PieChartData(
                                    pieTouchData: PieTouchData(
                                      touchCallback: (event, response) {
                                        setState(() {
                                          if (!event.isInterestedForInteractions ||
                                              response == null ||
                                              response.touchedSection == null) {
                                            _touchedIndex = -1;
                                            return;
                                          }
                                          _touchedIndex = response.touchedSection!.touchedSectionIndex;
                                        });
                                      },
                                    ),
                                    borderData: FlBorderData(show: false),
                                    sectionsSpace: 2,
                                    centerSpaceRadius: 45,
                                    sections: _pieChartSections,
                                  ),
                                  swapAnimationDuration: const Duration(milliseconds: 600),
                                  swapAnimationCurve: Curves.easeOutCubic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      const Text("Category-wise Spending",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),

                      ..._categorySpending.asMap().entries.map((entry) {
                        final color = _chartColors[entry.key % _chartColors.length];
                        final item = entry.value;
                        final percentage = (item.value / _totalExpenses * 100);
                        return _buildCategoryListItem(
                            item.key, item.value, percentage, color);
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, double amount, Color color, IconData icon,
      {bool isFullWidth = false}) {
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700])),
              Text(
                "₹${amount.toStringAsFixed(2)}",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ],
      ),
    );

    return isFullWidth ? card : Expanded(child: card);
  }

  Widget _buildCategoryListItem(
      String category, double amount, double percentage, Color color) {
    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, radius: 8),
        title: Text(category,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Text("${percentage.toStringAsFixed(1)}% of expenses",
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
        trailing: Text("₹${amount.toStringAsFixed(2)}",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
