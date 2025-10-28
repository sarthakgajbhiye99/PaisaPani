import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class ForecastChart extends StatelessWidget {
  final List<FlSpot> history;
  final List<FlSpot> forecast;

  const ForecastChart({
    super.key,
    required this.history,
    required this.forecast,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text("No historical data to display.")),
      );
    }

    // Combine all spots to find the min/max values
    final allSpots = [...history, ...forecast];
    
    // Find min/max for Y-axis (Amount)
    final allAmounts = allSpots.map((spot) => spot.y).toList();
    final minY = allAmounts.reduce((a, b) => a < b ? a : b).toDouble() * 0.8;
    final maxY = allAmounts.reduce((a, b) => a > b ? a : b).toDouble() * 1.2;

    // Find min/max for X-axis (Time)
    final allTimes = allSpots.map((spot) => spot.x).toList();
    final minX = allTimes.reduce((a, b) => a < b ? a : b).toDouble();
    final maxX = allTimes.reduce((a, b) => a > b ? a : b).toDouble();


    return AspectRatio(
      aspectRatio: 1.5,
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => Colors.blueGrey.withOpacity(0.9),
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  final date = DateTime.fromMillisecondsSinceEpoch(barSpot.x.toInt());
                  final amount = barSpot.y;
                  final isForecast = barSpot.barIndex == 1;

                  String title = DateFormat('MMM yyyy').format(date);
                  
                  return LineTooltipItem(
                    '$title\n',
                    TextStyle(
                      color: isForecast ? Colors.orange[100] : Colors.blue[100],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    children: [
                      TextSpan(
                        text: '₹${amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    textAlign: TextAlign.left,
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: (maxY - minY) / 4, // Dynamic grid lines
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
            getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: (maxX - minX) / 5, // Show ~5 labels
                getTitlesWidget: bottomTitleWidgets,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                getTitlesWidget: leftTitleWidgets,
              ),
            ),
          ),
          borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.withOpacity(0.5))),
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            // History Line (Blue, Solid)
            LineChartBarData(
              spots: history,
              isCurved: true,
              color: Colors.blue,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.1)),
            ),
            // Forecast Line (Orange, Dashed)
            LineChartBarData(
              spots: forecast,
              isCurved: true,
              color: Colors.orange,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              dashArray: [5, 5],
              belowBarData: BarAreaData(show: true, color: Colors.orange.withOpacity(0.1)),
            ),
          ],
        ),
      ),
    );
  }

  // --- Chart Title Widgets ---

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10);
    // Convert the 'value' (which is millisecondsSinceEpoch) back to a DateTime
    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    // Format it as 'MMM' (e.g., "Oct")
    final text = DateFormat('MMM').format(date);

    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 4,
      child: Text(text, style: style),
    );
  }

  Widget leftTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10);
    // Format large numbers (e.g., 12000 -> 12k)
    final formatter = NumberFormat.compact();
    String text = formatter.format(value);

    return Text(text, style: style, textAlign: TextAlign.right);
  }
}