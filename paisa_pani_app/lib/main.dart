import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'api_service.dart'; // <-- ADD THIS LINE
import 'widgets/forecast_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'monthly_report_screen.dart';
part 'main.g.dart'; // For Hive code generation

// --- UTILITY FUNCTION ---
String categorizeMerchant(String merchant) {
  final merchantLower = merchant.toLowerCase();
  if (merchantLower.contains('swiggy') || merchantLower.contains('zomato') || merchantLower.contains('restaurant') || merchantLower.contains('cafe')) return 'Food';
  if (merchantLower.contains('bigbasket') || merchantLower.contains('grofers') || merchantLower.contains('dmart') || merchantLower.contains('reliance fresh') || merchantLower.contains('more store') || merchantLower.contains('kirana')) return 'Groceries';
  if (merchantLower.contains('uber') || merchantLower.contains('ola') || merchantLower.contains('taxi') || merchantLower.contains('metro') || merchantLower.contains('irctc') || merchantLower.contains('redbus') || merchantLower.contains('flight') || merchantLower.contains('airline')) return 'Travel';
  if (merchantLower.contains('amazon') || merchantLower.contains('flipkart') || merchantLower.contains('myntra') || merchantLower.contains('ajio') || merchantLower.contains('shop') || merchantLower.contains('mall') || merchantLower.contains('trends') || merchantLower.contains('lifestyle')) return 'Shopping';
  if (merchantLower.contains('netflix') || merchantLower.contains('spotify') || merchantLower.contains('hotstar') || merchantLower.contains('prime video') || merchantLower.contains('bookmyshow') || merchantLower.contains('pvr') || merchantLower.contains('inox') || merchantLower.contains('cinema') || merchantLower.contains('movie')) return 'Entertainment';
  if (merchantLower.contains('apollo') || merchantLower.contains('pharmacy') || merchantLower.contains('medical') || merchantLower.contains('hospital') || merchantLower.contains('health') || merchantLower.contains('clinic') || merchantLower.contains('doctor') || merchantLower.contains('pharmeasy')) return 'Healthcare';
  if (merchantLower.contains('bill') || merchantLower.contains('electricity') || merchantLower.contains('recharge') || merchantLower.contains('utility') || merchantLower.contains('gas') || merchantLower.contains('broadband') || merchantLower.contains('water')) return 'Utilities';
  if (merchantLower.contains('food')) return 'Food';
  if (merchantLower.contains('grocery')) return 'Groceries';
  if (merchantLower.contains('travel') || merchantLower.contains('transport')) return 'Travel';
  if (merchantLower.contains('store')) return 'Shopping';
  if (merchantLower.contains('entertainment')) return 'Entertainment';
  if (merchantLower.contains('health')) return 'Healthcare';
  if (merchantLower.contains('petrol') || merchantLower.contains('fuel')) return 'Others';
  if (merchant.toUpperCase() == 'SALARY') return 'Income';
  if (merchant == 'N/A' || merchant.isEmpty) return 'Unknown';
  return 'Others';
}
// --- END UTILITY FUNCTION ---

// --- OCR HELPER FUNCTION (for compute) ---
class _OcrResult {
  final String fullText;
  final String shop;
  final String date;
  final String total;
  _OcrResult({ required this.fullText, required this.shop, required this.date, required this.total });
}
Future<_OcrResult> _processImageInIsolate(InputImage inputImage) async {
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final RecognizedText result = await textRecognizer.processImage(inputImage);
  final String fullText = result.text;

  if (kDebugMode) { // Only print in debug mode
    print("--- ML KIT RAW OUTPUT ---");
    print(fullText);
    print("--------------------------");
  }
  
  final String shop = extractShopName(result);
  final String date = extractDate(fullText);
  final String total = extractTotalAmount(fullText);
  await textRecognizer.close();
  return _OcrResult(fullText: fullText, shop: shop, date: date, total: total);
}
// --- END OCR HELPER ---


/// Manual/Scanned Expense data model
@HiveType(typeId: 0)
class Expense extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final double amount;
  @HiveField(3)
  final String category;
  @HiveField(4)
  final DateTime date;
  @HiveField(5)
  final String description;
  @HiveField(6)
  final String transactionType; // 'Debit' or 'Credit'

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    this.description = '',
    required this.transactionType,
  });
}

/// Service to manage manual/scanned expenses
class ExpenseService {
  static final Box<Expense> _expenseBox = Hive.box<Expense>('expenses');

  // Notifier to automatically update UI
  static final ValueNotifier<int> dataChanged = ValueNotifier(0);

  static void addExpense(Expense expense) {
    _expenseBox.put(expense.id, expense);
    dataChanged.value++; // Notify listeners
  }

  static void updateExpense(Expense updatedExpense) {
    _expenseBox.put(updatedExpense.id, updatedExpense);
    dataChanged.value++; // Notify listeners
  }

  static void deleteExpense(String id) {
    _expenseBox.delete(id);
    dataChanged.value++; // Notify listeners
  }

  static List<Expense> getExpenses() {
    final sortedExpenses = _expenseBox.values.toList();
    sortedExpenses.sort((a, b) => b.date.compareTo(a.date));
    return sortedExpenses;
  }

  static void clearExpenses() {
    _expenseBox.clear();
    dataChanged.value++; // Notify listeners
  }
}

// --- SMS PARSING LOGIC FOR INDIAN BANKS ---

/// SMS Transaction data model
class SmsTransaction {
  final String bankName;
  final String transactionType;
  final double amount;
  final String date;
  final String time;
  final String accountNumber;
  final String balance;
  final String merchantName;
  final String referenceNumber;
  final bool isSubtracted;

  SmsTransaction({
    required this.bankName,
    required this.transactionType,
    required this.amount,
    required this.date,
    required this.time,
    required this.accountNumber,
    required this.balance,
    required this.merchantName,
    required this.referenceNumber,
    this.isSubtracted = false,
  });

  SmsTransaction copyWith({bool? isSubtracted}) {
    return SmsTransaction(
      bankName: bankName,
      transactionType: transactionType,
      amount: amount,
      date: date,
      time: time,
      accountNumber: accountNumber,
      balance: balance,
      merchantName: merchantName,
      referenceNumber: referenceNumber,
      isSubtracted: isSubtracted ?? this.isSubtracted,
    );
  }
}

/// Parses Indian bank SMS messages to extract transaction details
SmsTransaction? parseIndianBankSms(String smsBody) {
  try {
    final bankPatterns = {
      'SBI': RegExp(r'State Bank of India|SBI', caseSensitive: false),
      'HDFC': RegExp(r'HDFC Bank|HDFC', caseSensitive: false),
      'ICICI': RegExp(r'ICICI Bank|ICICI', caseSensitive: false),
      'Axis': RegExp(r'Axis Bank|AXIS', caseSensitive: false),
      'Kotak': RegExp(r'Kotak Mahindra|Kotak', caseSensitive: false),
      'PNB': RegExp(r'Punjab National Bank|PNB', caseSensitive: false),
      'BOI': RegExp(r'Bank of India|BOI', caseSensitive: false),
      'Canara': RegExp(r'Canara Bank|CANARA', caseSensitive: false),
    };
    String bankName = 'Unknown Bank';
    for (final entry in bankPatterns.entries) {
      if (entry.value.hasMatch(smsBody)) { bankName = entry.key; break; }
    }

    double amount = 0.0;
    final decimalAmountRegex = RegExp(r'[₹]?\s?(\d[\d,]*\.\d{1,2})\b'); // 1 or 2 decimals
    Match? amountMatch = decimalAmountRegex.firstMatch(smsBody);

    if (amountMatch != null) {
      amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    } else {
      final keywordAmountRegex = RegExp(
          r'(?:debited by|Rs\.?|INR|[₹])\s*(\d[\d,]*)(?![\d.])',
          caseSensitive: false
      );
      amountMatch = keywordAmountRegex.firstMatch(smsBody);
      if (amountMatch != null) {
        amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
      }
    }

    String transactionType = 'Unknown';
    if (RegExp(r'debited|debit|spent|paid|purchase', caseSensitive: false).hasMatch(smsBody)) { transactionType = 'Debit'; }
    else if (RegExp(r'credited|credit|received|deposit', caseSensitive: false).hasMatch(smsBody)) { transactionType = 'Credit'; }

    final dateTimeRegex = RegExp(r'(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\s*(?:at|on)\s*(\d{1,2}:\d{2}(?::\d{2})?)', caseSensitive: false);
    final dateOnlyRegex = RegExp(r'\b(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\b');
    String date = 'N/A';
    String time = 'N/A';
    final dateTimeMatch = dateTimeRegex.firstMatch(smsBody);
    if (dateTimeMatch != null) {
      date = dateTimeMatch.group(1) ?? 'N/A';
      time = dateTimeMatch.group(2) ?? 'N/A';
    } else {
       final dateOnlyMatch = dateOnlyRegex.firstMatch(smsBody);
       if (dateOnlyMatch != null) { date = dateOnlyMatch.group(1) ?? 'N/A'; }
    }

    final accountRegex = RegExp(r'A/c\s*(?:No\.?)?\s*(?:ending\s+with|ending)?\s*(\*+[\dX]{2,4})\b', caseSensitive: false);
    final accountMatch = accountRegex.firstMatch(smsBody);
    String accountNumber = accountMatch?.group(1) ?? 'N/A';
     if (accountNumber == 'N/A') {
        final altAccountRegex = RegExp(r'Ac\s+(\*+\d{4})\b', caseSensitive: false);
         final altAccountMatch = altAccountRegex.firstMatch(smsBody);
         accountNumber = altAccountMatch?.group(1) ?? 'N/A';
     }

    final balanceRegex = RegExp(r'(?:Avl\.?|Avbl\.?|Available)\s+Bal(?:ance)?\s*[:\-]?\s*Rs\.?\s*([0-9,]+(?:\.\d{1,2})?)', caseSensitive: false);
    final balanceMatch = balanceRegex.firstMatch(smsBody);
    String balance = balanceMatch?.group(1)?.replaceAll(',', '') ?? 'N/A';

    String merchantName = 'N/A';
    RegExp merchantPattern1 = RegExp(r"at\s+([A-Za-z0-9\s.&'\-]+?)\s+(?:on|Avl\.? Bal|$|\.)", caseSensitive: false);
    RegExp merchantPattern2 = RegExp(r"Info:\s+.*?at\s+([A-Za-z0-9\s.&'\-]+?)(?:\s+Avl\.? Bal|$)", caseSensitive: false);

     Match? merchantMatch1 = merchantPattern1.firstMatch(smsBody);
     if (merchantMatch1 != null) {
         merchantName = merchantMatch1.group(1)!.trim();
     } else {
       Match? merchantMatch2 = merchantPattern2.firstMatch(smsBody);
         if (merchantMatch2 != null) {
             merchantName = merchantMatch2.group(1)!.trim();
         } else {
             RegExp vpaRegex = RegExp(r'(?:to|Payee[:]?)\s+([a-zA-Z0-9.\-_]+@[a-zA-Z]+)', caseSensitive: false);
             Match? vpaMatch = vpaRegex.firstMatch(smsBody);
             if (vpaMatch != null) {
               merchantName = vpaMatch.group(1)!.trim();
             } else {
                 RegExp merchantPatternFallback = RegExp(r"\bat\s+([A-Za-z0-9\s.&'\-]+?)(?:\s+on\b|\s+at\b|\s+Rs\.|\s+Bal|$)", caseSensitive: false);
                 Match? merchantMatchFallback = merchantPatternFallback.firstMatch(smsBody);
                 if (merchantMatchFallback != null) {
                     merchantName = merchantMatchFallback.group(1)?.trim() ?? 'N/A';
                 }
             }
         }
     }
     merchantName = merchantName.replaceAll(RegExp(r'\.$|sms$', caseSensitive: false),'').trim();
     merchantName = merchantName.replaceAll(RegExp(r'\s*\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\s*$'), '').trim();
     merchantName = merchantName.replaceAll(RegExp(r'\s*\d{1,2}:\d{2}(?::\d{2})?\s*$'), '').trim();

    final refRegex = RegExp(r'(?:Ref No|Ref:)\s*(\w+)', caseSensitive: false);
    final refMatch = refRegex.firstMatch(smsBody);
    String referenceNumber = refMatch?.group(1) ?? 'N/A';
     if (referenceNumber == 'N/A') {
        final upiRefRegex = RegExp(r'UPI Ref No[:]?\s*(\d+)', caseSensitive: false);
        final upiRefMatch = upiRefRegex.firstMatch(smsBody);
        referenceNumber = upiRefMatch?.group(1) ?? 'N/A';
     }

    return SmsTransaction(
      bankName: bankName, transactionType: transactionType, amount: amount,
      date: date, time: time, accountNumber: accountNumber, balance: balance,
      merchantName: merchantName, referenceNumber: referenceNumber,
    );
  } catch (e) {
    print('Error parsing SMS: $e\nSMS Body: $smsBody');
    return null;
  }
}

// --- IMPROVED EXTRACTION LOGIC ---
String extractShopName(RecognizedText recognizedText) {
  final potentialNames = recognizedText.blocks.take(7).map((block) => block.text.replaceAll('\n', ' ').trim()).where((text) => text.isNotEmpty && text.length > 2).toList();
  final junkKeywords = ['GSTIN', 'INVOICE', 'BILL TO', 'SHIP TO', 'TOTAL', 'AMOUNT', 'DATE', 'TIME', 'PHONE', 'MOBILE', 'PH:', 'MO:', 'PH.', 'MO.', 'TAX INVOICE', 'RECEIPT', 'CUSTOMER', 'NAME:', 'BALANCE', 'CHANGE', 'THANKS', 'VISIT AGAIN', 'WELCOME', 'INVOICE NO', 'BILL NO', 'ORDER NO', 'CASHIER:', 'SERVER:', 'TABLE NO', 'WWW.', '.COM', 'HTTP'];
  final addressKeywords = ['ROAD', ' RD', 'STREET', ' ST', 'NAGAR', 'NEAR', 'OPP', 'OPPOSITE', 'PINCODE', 'PIN:', 'FLOOR', 'COMPLEX', 'BUILDING', 'CITY', 'STATE', 'MUMBAI', 'PUNE', 'DELHI', 'CHENNAI', 'KOLKATA', 'BANGALORE', 'HYDERABAD', 'MAHARASHTRA', 'KARNATAKA', 'GUJARAT', ' NO:', 'HOUSE NO', 'FLAT NO', 'SHOP NO', 'PLOT NO', 'CROSS', 'MAIN'];
  final businessSuffixes = ['STORE', 'SHOP', 'ENTERPRISES', 'TRADERS', 'TRADING', 'COMPANY', 'PVT', 'LTD', 'PRIVATE', 'LIMITED', 'CORPORATION', 'CORP', 'MART', 'BAZAAR', 'MARKET', 'KIRANA', 'GENERAL', 'SUPERMARKET', 'MALL', 'PLAZA', 'HOTEL', 'RESTAURANT', 'BAKERY', 'CAFE', 'JEWELLERS', 'MOTORS', 'MEDICALS'];
  List<Map<String, dynamic>> candidates = [];
  int lineIndex = 0;
  for (final block in recognizedText.blocks.take(7)) {
    for (final line in block.lines) {
      String text = line.text.replaceAll('\n', ' ').trim();
      String upperText = text.toUpperCase();
      if (text.isEmpty || text.length < 3 || RegExp(r'^\d[\d\s-]{5,}$').hasMatch(text)) { continue; }
      int score = 0;
      if (junkKeywords.any((kw) => upperText.contains(kw))) { score -= 100; }
      if (addressKeywords.any((kw) => upperText.contains(kw))) { score -= 50; }
      if (RegExp(r'^[\d\s,./:-]+$').hasMatch(text)) { score -= 20; }
      if (lineIndex < 2) { score += 10; } else if (lineIndex < 5) { score += 5; }
      if (businessSuffixes.any((suffix) => upperText.contains(suffix))) { score += 25; }
      if (text == upperText && text.length > 3 && !RegExp(r'\d').hasMatch(text)) { score += 15; }
      if (text.length > 30) { score -= 10; }
      if (upperText.contains(' & ') || upperText.contains(' AND ')) { score += 5; }
      candidates.add({'text': text, 'score': score});
      lineIndex++;
    }
  }
  if (candidates.isEmpty) { return recognizedText.blocks.isNotEmpty ? recognizedText.blocks.first.text.replaceAll('\n', ' ').trim() : 'N/A'; }
  candidates.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
  String bestName = candidates.first['text'];
  int bestScore = candidates.first['score'];
  if (bestScore < 0 && recognizedText.blocks.isNotEmpty) { return recognizedText.blocks.first.text.replaceAll('\n', ' ').trim(); }
  return bestName;
}
String extractDate(String fullText) {
  final dateRegex = RegExp( r'(\b\d{1,2}[-./]\d{1,2}[-./]\d{2,4}\b)|' r'(\b\d{4}[-./]\d{1,2}[-./]\d{1,2}\b)|' r'(\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4}\b)|' r'(\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?,?\s+\d{2,4}\b)', caseSensitive: false);
  final matches = dateRegex.allMatches(fullText);
  if (matches.isNotEmpty) {
     final lines = fullText.split('\n');
     for (final line in lines) { if (line.toLowerCase().contains('date') || line.toLowerCase().contains('dt.')) { final matchInLine = dateRegex.firstMatch(line); if (matchInLine != null) { return matchInLine.group(0)!.replaceAll(',', '').trim(); } } }
    return matches.first.group(0)!.replaceAll(',', '').trim();
  } return 'N/A';
}
String extractTotalAmount(String fullText) {
  double maxAmountWithKeyword = -1.0; double largestAmountOverall = -1.0; String? amountStringWithKeyword; String? largestAmountStringOverall;
  final lines = fullText.split('\n');
  final amountRegex = RegExp(r'[₹\$€£]?\s?(\d{1,3}(?:(?:,\d{2})*(?:,\d{3}))*(?:\.\d{1,2})?|\d+(?:[.,]\d{1,2})?)');
  final keywords = ['total', 'amount', 'balance', 'due', 'grand total', 'net amount', 'payable', 'net pay', 'paid'];
   double? parseAmount(String? amountStr) { if (amountStr == null || amountStr.trim().isEmpty) return null; String cleanedAmount = amountStr.replaceAll(RegExp(r'[₹\$€£\s]'), ''); String standardCleaned = cleanedAmount.replaceAll(',', ''); double? parsedAmount = double.tryParse(standardCleaned); if (parsedAmount != null) return parsedAmount; if (cleanedAmount.contains(',') && cleanedAmount.contains('.')) { String europeanCleaned = cleanedAmount.replaceAll('.', '').replaceAll(',', '.'); parsedAmount = double.tryParse(europeanCleaned); if (parsedAmount != null) return parsedAmount; } if (cleanedAmount.contains(',') && !cleanedAmount.contains('.')) { int lastComma = cleanedAmount.lastIndexOf(','); if (lastComma != -1 && (cleanedAmount.length - lastComma - 1 <= 2)) { String commaAsDecimalCleaned = '${cleanedAmount.substring(0, lastComma).replaceAll(',', '')}.${cleanedAmount.substring(lastComma + 1)}'; parsedAmount = double.tryParse(commaAsDecimalCleaned); if (parsedAmount != null) return parsedAmount; } String commaAsThousandCleaned = cleanedAmount.replaceAll(',', ''); parsedAmount = double.tryParse(commaAsThousandCleaned); if (parsedAmount != null) return parsedAmount; } parsedAmount = double.tryParse(cleanedAmount); if (parsedAmount != null) return parsedAmount; return null; }
  for (int i = 0; i < lines.length; i++) { final lowerLine = lines[i].toLowerCase(); bool keywordFound = keywords.any((kw) => lowerLine.contains(kw)); final matchesOnLine = amountRegex.allMatches(lines[i]); if (matchesOnLine.isNotEmpty) { for (final match in matchesOnLine) { final amountStr = match.group(0); final potentialAmount = parseAmount(amountStr); if (potentialAmount != null) { if (potentialAmount > largestAmountOverall) { largestAmountOverall = potentialAmount; largestAmountStringOverall = amountStr; } if (keywordFound && potentialAmount > maxAmountWithKeyword) { maxAmountWithKeyword = potentialAmount; amountStringWithKeyword = amountStr; } } } } else if (keywordFound && i + 1 < lines.length) { final matchesOnNextLine = amountRegex.allMatches(lines[i+1]); for (final match in matchesOnNextLine) { final amountStr = match.group(0); final potentialAmount = parseAmount(amountStr); if (potentialAmount != null) { if (potentialAmount > largestAmountOverall) { largestAmountOverall = potentialAmount; largestAmountStringOverall = amountStr; } if (potentialAmount > maxAmountWithKeyword) { maxAmountWithKeyword = potentialAmount; amountStringWithKeyword = amountStr; } } } } }
   if (amountStringWithKeyword != null) { return parseAmount(amountStringWithKeyword)?.toStringAsFixed(2) ?? 'N/A'; } else if (largestAmountStringOverall != null) { return parseAmount(largestAmountStringOverall)?.toStringAsFixed(2) ?? 'N/A'; } return 'N/A';
}

// --- SMS SERVICE ---
class SmsService {
  // This list is no longer used to store data, but can be used for temporary parsing
  // static final List<SmsTransaction> _transactions = []; // Removed
  
  static void clearTransactions() {
    // This now does nothing, as SMS data is not stored here.
  }
  
  // These methods are no longer needed as we don't store SMS transactions separately.
  static void subtractCreditTransaction(int index) {}
  static void restoreCreditTransaction(int index) {}
  static double calculateNetBalance() => 0.0;
  
  static Future<void> initialize() async { /* Placeholder */ }

  static Future<bool> requestSmsPermissions() async {
    final status = await Permission.sms.request();
    print("SMS Permission Status: $status");
    return status.isGranted;
  }

  static Future<void> startSmsListener() async {
    // This function is now just a trigger for _refreshData on the dashboard.
    print("SmsService: startSmsListener called (triggers UI refresh).");
  }

  // This no longer returns any meaningful data.
  static List<SmsTransaction> getTransactions() => [];
}

// --- MAIN APP ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // --- HIVE INITIALIZATION ---
  await Hive.initFlutter();
  await Hive.openBox('settings'); // Open simple settings box
  Hive.registerAdapter(ExpenseAdapter()); // Register generated adapter

  try {
    await Hive.openBox<Expense>('expenses');
  } catch (e) {
    print("Error opening Hive box (likely schema mismatch): $e");
    print("Deleting box and recreating...");
    await Hive.deleteBoxFromDisk('expenses'); // Delete the corrupt box
    await Hive.openBox<Expense>('expenses'); // Re-open the (now empty) box
  }
  // --- END HIVE INITIALIZATION ---

  await SmsService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paisa Pani - Personal Finance',
       debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.teal).copyWith(secondary: Colors.amber),
         useMaterial3: true,
         appBarTheme: const AppBarTheme( backgroundColor: Colors.teal, foregroundColor: Colors.white, elevation: 1, centerTitle: true),
         cardTheme: CardThemeData(
           elevation: 2,
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0)
         ),
           inputDecorationTheme: InputDecorationTheme( border: OutlineInputBorder( borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.teal, width: 2)), contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12)),
            elevatedButtonTheme: ElevatedButtonThemeData( style: ElevatedButton.styleFrom( backgroundColor: Colors.teal, foregroundColor: Colors.white, shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16))),
      ),
      home: const HomeScreen(),
    );
  }
}

// --- HOME SCREEN (WITH BOTTOM NAV) ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // --- WIDGET LIST IS NOW ALL CONST ---
  static final List<Widget> _widgetOptions = <Widget>[
    const DashboardScreen(),
    const SmsTransactionScreen(),
    const MonthlyReportScreen(),
    const BudgetForecastScreen(), // <-- No parameters needed
    const FinancialAdvisorScreen(),
  ];
  

  void _onItemTapped(int index) {
     setState(() {
       _selectedIndex = index;
     });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: IndexedStack(
           index: _selectedIndex,
           children: _widgetOptions,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem( icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem( icon: Icon(Icons.sms_outlined), activeIcon: Icon(Icons.sms), label: 'SMS'),
          BottomNavigationBarItem( icon: Icon(Icons.pie_chart_outline), activeIcon: Icon(Icons.pie_chart), label: 'Reports'),
          BottomNavigationBarItem( icon: Icon(Icons.show_chart_outlined), activeIcon: Icon(Icons.show_chart), label: 'Forecast'),
          BottomNavigationBarItem( icon: Icon(Icons.lightbulb_outline), activeIcon: Icon(Icons.lightbulb), label: 'Advice'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey[600],
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedFontSize: 12,
        unselectedFontSize: 12,
      ),
    );
  }
}

// --- ADD EXPENSE SCREEN ---
class AddExpenseScreen extends StatefulWidget {
  final String? initialTitle;
  final String? initialAmount;
  final DateTime? initialDate;
  final String? initialDescription;
  final Expense? existingExpense;
  final String? initialCategory;

  const AddExpenseScreen({
    super.key,
    this.initialTitle,
    this.initialAmount,
    this.initialDate,
    this.initialDescription,
    this.existingExpense,
    this.initialCategory,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedCategory = 'Food';
  late DateTime _selectedDate;
  String _selectedType = 'Expense'; // 'Expense' or 'Income'

  final List<String> _categories = [ 'Entertainment', 'Food', 'Groceries', 'Healthcare', 'Shopping', 'Travel', 'Utilities', 'Others' ];

   @override
  void initState() {
    super.initState();
    if (widget.existingExpense != null) {
      // We are EDITING an existing expense
      _titleController.text = widget.existingExpense!.title;
      _amountController.text = widget.existingExpense!.amount.toStringAsFixed(2);
      _selectedDate = widget.existingExpense!.date;
      _descriptionController.text = widget.existingExpense!.description;
      _selectedCategory = widget.existingExpense!.category;
      _selectedType = widget.existingExpense!.transactionType == 'Credit' ? 'Income' : 'Expense';
    } else {
      // We are ADDING a new one (maybe pre-filled)
      _titleController.text = widget.initialTitle ?? '';
      _amountController.text = widget.initialAmount ?? '';
      _selectedDate = widget.initialDate ?? DateTime.now();
      _descriptionController.text = widget.initialDescription ?? '';
      _selectedType = 'Expense'; // Default to expense
    }
      // Auto-select category
if (widget.initialCategory != null && _categories.contains(widget.initialCategory)) {
  // 1. Priority: Use the category from the scanner/SMS
  _selectedCategory = widget.initialCategory!;
} else if (widget.initialTitle != null && widget.initialTitle!.isNotEmpty) {
  // 2. Fallback: Guess from the title
  String potentialCategory = categorizeMerchant(widget.initialTitle!);
  if (_categories.contains(potentialCategory)) {
    _selectedCategory = potentialCategory;
  }
}
  }
  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
     if (!mounted) return;
    final DateTime? picked = await showDatePicker(
      context: context, initialDate: _selectedDate,
      firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && picked != _selectedDate) {
      if (!mounted) return;
      setState(() { _selectedDate = picked; });
    }
  }

  void _saveExpense() {
    final String title = _titleController.text.trim();
    final String amountText = _amountController.text.trim();
    final String description = _descriptionController.text.trim();

     if (!mounted) return;
    if (title.isEmpty || amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Please enter title and amount')));
      return;
    }
    final double? amount = double.tryParse(amountText.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Please enter a valid positive amount')));
      return;
    }

    final String transactionType = _selectedType == 'Income' ? 'Credit' : 'Debit';
    final String category = _selectedType == 'Income' ? 'Income' : _selectedCategory;

    if (widget.existingExpense != null) {
      // UPDATE existing expense
      final updatedExpense = Expense(
        id: widget.existingExpense!.id,
        title: title,
        amount: amount,
        category: category,
        date: _selectedDate,
        description: description,
        transactionType: transactionType,
      );
      ExpenseService.updateExpense(updatedExpense);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar( content: Text('Updated "$title"'), backgroundColor: Colors.blue, duration: const Duration(seconds: 2)),
      );

    } else {
      // ADD new expense
      final newExpense = Expense(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        amount: amount,
        category: category,
        date: _selectedDate,
        description: description,
        transactionType: transactionType,
      );
      ExpenseService.addExpense(newExpense);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar( content: Text('Added "$title"'), backgroundColor: Colors.green, duration: const Duration(seconds: 2), ),
      );
    }

    Navigator.of(context).pop();
  }
  
  Future<void> _showDeleteConfirmation() async {
    if (!mounted || widget.existingExpense == null) return;
    
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Expense?'),
          content: const Text('Are you sure you want to permanently delete this expense?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      ExpenseService.deleteExpense(widget.existingExpense!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
      );
      Navigator.of(context).pop(); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingExpense != null ? 'Edit Transaction' : 'Add Transaction'),
        actions: [
          if (widget.existingExpense != null)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete Transaction',
              onPressed: _showDeleteConfirmation,
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
         child: Column(
         crossAxisAlignment: CrossAxisAlignment.stretch,
           children: [
               SegmentedButton<String>(
                 segments: const [
                   ButtonSegment(value: 'Expense', label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
                   ButtonSegment(value: 'Income', label: Text('Income'), icon: Icon(Icons.arrow_downward)),
                 ],
                 selected: {_selectedType},
                 onSelectionChanged: (Set<String> newSelection) {
                   setState(() {
                     _selectedType = newSelection.first;
                   });
                 },
                 style: SegmentedButton.styleFrom(
                   selectedBackgroundColor: _selectedType == 'Expense' ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                   selectedForegroundColor: _selectedType == 'Expense' ? Colors.red.shade900 : Colors.green.shade900,
                   foregroundColor: Colors.grey.shade600,
                 ),
               ),
               const SizedBox(height: 24),
               
               TextField( controller: _titleController, decoration: InputDecoration( labelText: '$_selectedType Title *', hintText: 'e.g., Lunch, Salary', prefixIcon: const Icon(Icons.label_outline)), textInputAction: TextInputAction.next),
               const SizedBox(height: 16),
               TextField( controller: _amountController, decoration: const InputDecoration( labelText: 'Amount *', hintText: '0.00', prefixText: '₹ ', prefixIcon: Icon(Icons.currency_rupee)), keyboardType: const TextInputType.numberWithOptions(decimal: true), textInputAction: TextInputAction.next),
               const SizedBox(height: 16),

               if (_selectedType == 'Expense')
                 DropdownButtonFormField<String>( 
                   value: _selectedCategory, 
                   decoration: const InputDecoration( labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)), 
                   items: _categories.map((String category) { return DropdownMenuItem<String>( value: category, child: Text(category)); }).toList(), 
                   onChanged: (String? newValue) { if (newValue != null) { setState(() { _selectedCategory = newValue; }); } }
                 )
               else
                 const SizedBox.shrink(), // Hide category dropdown if Income

               const SizedBox(height: 16),
               InkWell( onTap: _selectDate, child: InputDecorator( decoration: const InputDecoration( labelText: 'Date', prefixIcon: Icon(Icons.calendar_today_outlined)), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text( DateFormat('dd MMM yyyy').format(_selectedDate), style: const TextStyle(fontSize: 16)), const Icon(Icons.arrow_drop_down, color: Colors.grey)],),),),
               const SizedBox(height: 16),
               TextField( controller: _descriptionController, decoration: const InputDecoration( labelText: 'Description (Optional)', hintText: 'Add any additional notes...', prefixIcon: Icon(Icons.note_alt_outlined)), maxLines: 3, textInputAction: TextInputAction.done, onSubmitted: (_) => _saveExpense()),
               const SizedBox(height: 32),
               ElevatedButton.icon( onPressed: _saveExpense, icon: const Icon(Icons.save), label: const Text('Save Transaction')),
               const SizedBox(height: 16)
           ],
        ),
      ),
    );
  }
}

// --- DASHBOARD SCREEN ---
class DashboardScreen extends StatefulWidget { const DashboardScreen({super.key}); @override State<DashboardScreen> createState() => _DashboardScreenState(); }
class _DashboardScreenState extends State<DashboardScreen> {
  final settingsBox = Hive.box('settings');
  double _manualIncome = 0.0;
  bool _hasManualIncome = false;
  double _totalCredit = 0.0;
  double _totalDebit = 0.0;
  double _netBalance = 0.0;
  Map<String, double> _categorySpending = {};
  List<Expense> _allExpenses = [];
  int _transactionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadManualIncome();
    ExpenseService.dataChanged.addListener(_refreshData);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  @override
  void dispose() {
    ExpenseService.dataChanged.removeListener(_refreshData);
    super.dispose();
  }

  void _loadManualIncome() {
    _manualIncome = settingsBox.get('manualIncome', defaultValue: 0.0);
    _hasManualIncome = settingsBox.get('hasManualIncome', defaultValue: false);
  }

  Future<void> _refreshData() async {
    _calculateAndSetMetrics();
  }

  void _calculateAndSetMetrics() {
    // Note: SmsService.getTransactions() is no longer used here.
    final manualExpenses = ExpenseService.getExpenses();
    double calculatedTotalCredit = 0;
    double calculatedTotalDebit = 0;
    Map<String, double> calculatedCategorySpending = {};

    for (final expense in manualExpenses) {
      if (expense.transactionType == 'Credit') {
        calculatedTotalCredit += expense.amount;
      } else {
        calculatedTotalDebit += expense.amount;
        final category = expense.category;
        calculatedCategorySpending[category] = (calculatedCategorySpending[category] ?? 0) + expense.amount;
      }
    }

    if (_hasManualIncome) {
      calculatedTotalCredit += _manualIncome;
    }
    double calculatedNetBalance = calculatedTotalCredit - calculatedTotalDebit;

     if (mounted) {
       setState(() {
         _totalCredit = calculatedTotalCredit;
         _totalDebit = calculatedTotalDebit;
         _netBalance = calculatedNetBalance;
         _categorySpending = calculatedCategorySpending;
         _allExpenses = manualExpenses; 
         _transactionCount = manualExpenses.length;
       });
     }
  }

  Future<void> _showResetConfirmationDialog() async {
    if (!mounted) return;
    final bool? shouldReset = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Reset All Data'),
          content: const Text('Are you sure you want to remove all manually added, scanned, and SMS-added expenses? This action cannot be undone.'),
          actions: <Widget>[
            TextButton( child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop(false)),
            TextButton( style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Reset All'), onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        );
      },
    );
    if (shouldReset == true) { _resetAllTransactions(); }
  }

  void _resetAllTransactions() {
    ExpenseService.clearExpenses();
    // SmsService.clearTransactions(); // No longer needed

    setState(() {
      _manualIncome = 0.0;
      _hasManualIncome = false;
    });
    settingsBox.put('manualIncome', 0.0);
    settingsBox.put('hasManualIncome', false);

    _refreshData(); // Refresh metrics
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar( const SnackBar( content: Text('All added expenses have been reset.'), backgroundColor: Colors.orange, duration: Duration(seconds: 3))); }
  }

  void _showEditIncomeDialog() {
    final TextEditingController incomeController = TextEditingController( text: _hasManualIncome ? _manualIncome.toStringAsFixed(0) : '');
    if (!mounted) return;
    showDialog( context: context, builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Edit Total Income'),
          content: Column( mainAxisSize: MainAxisSize.min, children: [
             const Text('Enter approximate monthly income.', style: TextStyle(fontSize: 14, color: Colors.grey)), const SizedBox(height: 16),
             TextField( controller: incomeController, decoration: const InputDecoration( labelText: 'Monthly Income', prefixText: '₹ ', border: OutlineInputBorder(), hintText: 'e.g., 50000'), keyboardType: const TextInputType.numberWithOptions(decimal: false), autofocus: true),
           ]),
          actions: [
            TextButton( onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            TextButton( onPressed: () { 
             Navigator.of(dialogContext).pop(); 
             if (!mounted) return; 
             setState(() { _hasManualIncome = false; _manualIncome = 0.0; });
             settingsBox.put('manualIncome', 0.0);
             settingsBox.put('hasManualIncome', false);
             ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Manual income cleared'))); 
             _calculateAndSetMetrics(); 
            }, child: const Text('Clear')),
            ElevatedButton( onPressed: () { 
             final String incomeText = incomeController.text.trim(); 
             Navigator.of(dialogContext).pop(); 
             if (incomeText.isNotEmpty) { 
               final double? income = double.tryParse(incomeText.replaceAll(',', '')); 
               if (income != null && income >= 0) { 
                 if (!mounted) return; 
                 setState(() { _manualIncome = income; _hasManualIncome = true; });
                 settingsBox.put('manualIncome', income);
                 settingsBox.put('hasManualIncome', true);
                 ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text('Income updated to ₹${income.toStringAsFixed(0)}'), backgroundColor: Colors.green)); 
                 _calculateAndSetMetrics(); 
               } else { 
                 if (!mounted) return; 
                 ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Please enter a valid amount'))); 
               } 
             } else { 
               if (!mounted) return; 
               setState(() { _hasManualIncome = false; _manualIncome = 0.0; });
               settingsBox.put('manualIncome', 0.0);
               settingsBox.put('hasManualIncome', false);
               ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Manual income cleared'))); 
               _calculateAndSetMetrics(); 
             } 
            }, child: const Text('Save')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Expense> recentItems = _allExpenses.take(4).toList();
    return Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard'),
            actions: [ IconButton( icon: const Icon(Icons.delete_sweep_outlined), tooltip: 'Reset All Data', onPressed: _showResetConfirmationDialog) ]
        ),
        body: RefreshIndicator(
          onRefresh: _refreshData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row( children: [ Expanded( child: _buildEditableMetricCard( 'Total Income', '₹${_totalCredit.toStringAsFixed(2)}', Colors.green, Icons.trending_up, onEdit: _showEditIncomeDialog, isEditable: true, tooltip: 'Tap pencil to set manual income', hasManualIncome: _hasManualIncome)), const SizedBox(width: 12), Expanded( child: _buildMetricCard( 'Total Expenses', '₹${_totalDebit.toStringAsFixed(2)}', Colors.red, Icons.trending_down)), ]),
                const SizedBox(height: 12),
                Row( children: [ Expanded( child: _buildMetricCard( 'Net Balance', '₹${_netBalance.toStringAsFixed(2)}', _netBalance >= 0 ? Colors.blue : Colors.orange, Icons.account_balance_wallet)), const SizedBox(width: 12), Expanded( child: _buildMetricCard( 'Transactions', '$_transactionCount', Colors.purple, Icons.receipt_long)), ]),
                const SizedBox(height: 24),
                if (_categorySpending.isNotEmpty) ...[ const Text( 'Spending by Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)), const SizedBox(height: 12), Card( child: Padding( padding: const EdgeInsets.all(16.0), child: Column( children: () { final categoryEntries = _categorySpending.entries.toList(); categoryEntries.sort((a, b) => b.value.compareTo(a.value)); if (categoryEntries.isEmpty) return [const Text("No spending data.")]; return categoryEntries.take(5).map((entry) => Padding( padding: const EdgeInsets.symmetric(vertical: 6.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text(entry.key, style: const TextStyle(fontSize: 14)), Text( '₹${entry.value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), ], ), )).toList(); }(), ), ), ), const SizedBox(height: 24), ],
                const Text( 'Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)), const SizedBox(height: 12),
                if (recentItems.isEmpty) Card( child: Padding( padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0), child: Center( child: Column( mainAxisSize: MainAxisSize.min, children: [ const Icon(Icons.receipt_long, size: 48, color: Colors.grey), const SizedBox(height: 16), const Text( 'No transactions yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)), const SizedBox(height: 8), Text( 'Load SMS or add transactions manually.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])), const SizedBox(height: 16), ElevatedButton.icon( 
                 onPressed: () { 
                   context.findAncestorStateOfType<_HomeScreenState>()?._onItemTapped(1);
                 }, 
                 icon: const Icon(Icons.sms), 
                 label: const Text('Go to SMS')), 
                ], ), ), ), )
                else ListView.separated( 
                 shrinkWrap: true, 
                 physics: const NeverScrollableScrollPhysics(), 
                 itemCount: recentItems.length, 
                 itemBuilder: (context, index) { 
                   final item = recentItems[index];
                   return TransactionListTile(
                     expense: item, 
                     onRefresh: _refreshData,
                   );
                 }, 
                 separatorBuilder: (context, index) => const Divider(height: 1), 
                ),
                if (_allExpenses.isNotEmpty) Padding( padding: const EdgeInsets.only(top: 8.0), child: TextButton( onPressed: () { Navigator.push( context, MaterialPageRoute(builder: (context) => const AllTransactionsScreen())); }, child: const Text('View All Transactions ->')), ),
                const SizedBox(height: 24),
                const Text( 'Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)), const SizedBox(height: 12),
                Row( children: [ Expanded( child: ElevatedButton.icon( onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const AddExpenseScreen())); }, icon: const Icon(Icons.add_card_outlined), label: const Text('Add Transaction'))), const SizedBox(width: 12), Expanded( child: ElevatedButton.icon( onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const ReceiptScannerScreen())); }, icon: const Icon(Icons.camera_alt), label: const Text('Scan Bill'), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue))), ], ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        )
    );
  }

  Widget _buildMetricCard(String title, String value, Color color, IconData icon) { return Card( child: Padding( padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Row( children: [ Icon(icon, color: color, size: 20), const SizedBox(width: 8), Expanded( child: Text( title, style: const TextStyle(fontSize: 13, color: Colors.grey), overflow: TextOverflow.ellipsis)), ], ), const SizedBox(height: 8), Text( value, style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis), ], ), ), ); }
  Widget _buildEditableMetricCard( String title, String value, Color color, IconData icon, { required VoidCallback onEdit, required bool isEditable, String? tooltip, bool hasManualIncome = false}) { return Card( child: Padding( padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Row( children: [ Icon(icon, color: color, size: 20), const SizedBox(width: 8), Expanded( child: Text( title, style: const TextStyle(fontSize: 13, color: Colors.grey), overflow: TextOverflow.ellipsis)), if (isEditable) InkWell( onTap: onEdit, borderRadius: BorderRadius.circular(4), child: ConstrainedBox( constraints: const BoxConstraints(minWidth: 40, minHeight: 40), child: Tooltip( message: tooltip ?? 'Edit', child: Padding( padding: const EdgeInsets.all(4.0), child: Icon( Icons.edit, size: 18, color: Colors.grey.shade700))))), ], ), const SizedBox(height: 8), Text( value, style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis), if (hasManualIncome && title == 'Total Income') ...[ const SizedBox(height: 4), Text( 'Manual income included', style: TextStyle( fontSize: 10, color: Colors.grey.shade600)), ] ], ), ), ); }
}

// --- RECEIPT SCANNER SCREEN ---
class ReceiptScannerScreen extends StatefulWidget { const ReceiptScannerScreen({super.key}); @override State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState(); }
class _ReceiptScannerScreenState extends State<ReceiptScannerScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedImage;
  bool _isProcessing = false;
  String _parsedShop = 'N/A';
  String _parsedDate = 'N/A';
  String _parsedTotal = 'N/A';
  String? _fullParsedText;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (!mounted) return;
    setState(() { _isProcessing = true; _selectedImage = null; _parsedShop = 'N/A'; _parsedDate = 'N/A'; _parsedTotal = 'N/A'; _fullParsedText = null; _errorMessage = null; });

    try {
      final XFile? image = await _imagePicker.pickImage(source: source, imageQuality: 80);
      if (image == null) { if (mounted) setState(() => _isProcessing = false); return; }

      final inputImage = InputImage.fromFilePath(image.path);
      final _OcrResult ocrResult = await compute(_processImageInIsolate, inputImage);
      
      final String fullText = ocrResult.fullText;
      final String shop = ocrResult.shop;
      final String dateStr = ocrResult.date;
      final String totalStr = ocrResult.total;

      bool expenseAdded = false;
      if (totalStr != 'N/A') {
        final double? amount = double.tryParse(totalStr.replaceAll(RegExp(r'[^\d.]'), ''));
        DateTime expenseDate = DateTime.now();
        try {
          List<String> formats = ['dd/MM/yyyy', 'dd-MM-yyyy', 'dd.MM.yyyy', 'yyyy/MM/dd', 'yyyy-MM-dd', 'yyyy.MM.dd', 'dd MMM yyyy', 'MMM dd yyyy'];
          for (var format in formats) { try { expenseDate = DateFormat(format).parseLoose(dateStr.replaceAll(',', '')); break; } catch (_) {/* Try next */} }
        } catch (e) { print("Could not parse date from receipt: $dateStr"); }

        if (amount != null && amount > 0) {
          final List<String> categories = ['Entertainment', 'Food', 'Groceries', 'Healthcare', 'Shopping', 'Travel', 'Utilities', 'Others'];
          String category = 'Others';
          String potentialCategory = categorizeMerchant(shop);
          if (categories.contains(potentialCategory)) { category = potentialCategory; }

          final newExpense = Expense(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: shop == 'N/A' ? 'Scanned Expense' : shop,
            amount: amount,
            category: category,
            date: expenseDate,
            description: "Scanned from receipt.\n\n$fullText",
            transactionType: 'Debit',
          );
          ExpenseService.addExpense(newExpense);
          expenseAdded = true;
        }
      }

      if (!mounted) return;
      setState(() { _selectedImage = image; _parsedShop = shop; _parsedDate = dateStr; _parsedTotal = totalStr; _fullParsedText = fullText; _isProcessing = false; });

      if (expenseAdded && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Expense added automatically: ₹$totalStr from $shop'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ));
      } else if (totalStr == 'N/A' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not extract total amount to add expense automatically.'),
          duration: Duration(seconds: 3),
        ));
      }
    } catch (e) {
      print('Error processing image: $e');
      if (mounted) { setState(() { _isProcessing = false; _errorMessage = 'Failed to process image. Please ensure clear lighting and text.'; }); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Scanner')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Scan a bill using your camera or gallery.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isProcessing)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text("Processing image..."),
                    ],
                  ),
                ),
              )
            else ...[
              if (_selectedImage != null)
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_selectedImage!.path),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              if (_selectedImage != null) const SizedBox(height: 16),
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
              if (_errorMessage != null) const SizedBox(height: 12),
              if (_selectedImage != null && _errorMessage == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Extracted Details:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const Divider(height: 16),
                        _buildResultRow(Icons.store, 'Shop:', _parsedShop),
                        _buildResultRow(Icons.calendar_today, 'Date:', _parsedDate),
                        _buildResultRow(Icons.currency_rupee, 'Total:', _parsedTotal),
                      ],
                    ),
                  ),
                ),
              if (_selectedImage == null && !_isProcessing)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_search, size: 60, color: Colors.grey),
                        SizedBox(height: 16),
                        Text("Select an image to scan", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Text('$label ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

// --- BUDGET FORECAST SCREEN ---
class BudgetForecastScreen extends StatefulWidget {
  const BudgetForecastScreen({super.key});

  @override
  State<BudgetForecastScreen> createState() => _BudgetForecastScreenState();
}

class _BudgetForecastScreenState extends State<BudgetForecastScreen> {
  final ApiService _apiService = ApiService();
  final settingsBox = Hive.box('settings'); // Access settings box

  // Chart data
  List<FlSpot> _historySpots = [];
  List<FlSpot> _forecastSpots = [];

  // State variables
  bool _isLoading = true;
  String _errorMessage = '';
  
  // New "More Info" variables
  double _totalForecastedSpend = 0.0;
  double _manualIncome = 0.0;
  double _percentageChange = 0.0;
  List<MapEntry<String, double>> _topCategories = [];


  @override
  void initState() {
    super.initState();
    ExpenseService.dataChanged.addListener(_loadAndProcessData);
    _loadAndProcessData(); // Load data when the screen is first opened
  }

  @override
  void dispose() {
    ExpenseService.dataChanged.removeListener(_loadAndProcessData);
    super.dispose();
  }

  /// Fetches local data, sends it to the API, and prepares all chart data and stats
  Future<void> _loadAndProcessData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Load all data simultaneously
      final allExpenses = ExpenseService.getExpenses();
      _manualIncome = settingsBox.get('manualIncome', defaultValue: 0.0);

      // --- 1. Aggregate local data for History ---
      final Map<DateTime, double> monthlyTotals = {};
      for (final exp in allExpenses.where((e) => e.transactionType == 'Debit')) {
        final monthKey = DateTime(exp.date.year, exp.date.month, 1);
        monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + exp.amount;
      }
      
      // Check for minimum data
      if (monthlyTotals.length < 3) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Not enough data. Add at least 3 different months of expenses to see a forecast.';
            _historySpots = [];
            _forecastSpots = [];
          });
        }
        _prepareChartData({}, []); // Call to clear chart
        return;
      }

      // --- 2. Get Forecast from API ---
      final List<Map<String, dynamic>> forecastApiResult = 
          await _apiService.getForecast(allExpenses);

      if (forecastApiResult.isEmpty && mounted) {
         setState(() {
           _isLoading = false;
           _errorMessage = 'Could not generate a forecast. The API may be offline or initializing.';
         });
         return;
      }

      // --- 3. Prepare Chart Data ---
      _prepareChartData(monthlyTotals, forecastApiResult);

      // --- 4. Calculate "More Info" Stats ---
      // Total Forecast
      double totalForecast = 0.0;
      for (var item in forecastApiResult) {
        totalForecast += (item['predicted_expense'] as num);
      }
      
      // % Change vs. Last Month
      final sortedKeys = monthlyTotals.keys.toList()..sort();
      double lastActualSpend = monthlyTotals[sortedKeys.last] ?? 0.0;
      double firstForecastSpend = forecastApiResult.first['predicted_expense'];
      double percentChange = (lastActualSpend > 0) 
          ? ((firstForecastSpend - lastActualSpend) / lastActualSpend) * 100 
          : 0.0;

      // Top Drivers (from last 30 days)
      final historyStartDate = DateTime.now().subtract(const Duration(days: 30));
      final recentExpenses = allExpenses.where((e) => e.transactionType == 'Debit' && e.date.isAfter(historyStartDate));
      final Map<String, double> categoryMap = {};
      for (var exp in recentExpenses) {
        categoryMap[exp.category] = (categoryMap[exp.category] ?? 0) + exp.amount;
      }
      final sortedCategories = categoryMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));


      // --- 5. Set State with All New Info ---
      if (mounted) {
        setState(() {
          _totalForecastedSpend = totalForecast;
          _percentageChange = percentChange;
          _topCategories = sortedCategories.take(3).toList();
          _isLoading = false;
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to load forecast:\n${e.toString()}";
        });
      }
    }
  }

  /// Converts raw data into FlSpot lists for the chart
  void _prepareChartData(
    Map<DateTime, double> historyMap,
    List<Map<String, dynamic>> forecastList,
  ) {
    // Prepare History Spots (Show last 6 months of history)
    final sortedHistoryKeys = historyMap.keys.toList()..sort();
    final visibleHistoryKeys = sortedHistoryKeys.length <= 6 
        ? sortedHistoryKeys 
        : sortedHistoryKeys.sublist(sortedHistoryKeys.length - 6);

    final List<FlSpot> historySpots = visibleHistoryKeys.map((date) {
      return FlSpot(
        date.millisecondsSinceEpoch.toDouble(), // X-axis is time
        historyMap[date]!,                       // Y-axis is amount
      );
    }).toList();

    // Prepare Forecast Spots
    final List<FlSpot> forecastSpots = [];
    
    if (historySpots.isNotEmpty) {
      forecastSpots.add(historySpots.last); // Connect to last history point
    }
    
    for (final forecast in forecastList) {
      final month = DateTime.parse(forecast['month'] as String);
      final amount = (forecast['predicted_expense'] as num).toDouble();
      forecastSpots.add(FlSpot(
        month.millisecondsSinceEpoch.toDouble(),
        amount,
      ));
    }

    if (mounted) {
      setState(() {
        _historySpots = historySpots;
        _forecastSpots = forecastSpots;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Budget Forecast"),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Forecast',
            onPressed: _loadAndProcessData,
          )
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : (_errorMessage.isNotEmpty || _historySpots.isEmpty)
                ? _buildMessageUI(_errorMessage.isNotEmpty ? _errorMessage : 'Not enough expense data to create a forecast.')
                : _buildForecastUI(),
      ),
    );
  }

  /// The main UI when data is successfully loaded
  Widget _buildForecastUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ForecastChart(history: _historySpots, forecast: _forecastSpots),
          const SizedBox(height: 16),
          Text(
            "Blue = Actual Monthly Spend | Orange = Predicted Spend",
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          // --- "vs. Income" Alert Card ---
          _buildIncomeAlertCard(),
          
          const SizedBox(height: 16),
          
          // --- Key Metric Cards ---
          Row(
            children: [
              _buildStatCard(
                "Forecast Total (3 Mo)",
                "₹${_totalForecastedSpend.toStringAsFixed(2)}",
                Icons.trending_up,
                Colors.orange,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                "vs. Last Month",
                "${_percentageChange.toStringAsFixed(0)}%",
                _percentageChange >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                _percentageChange >= 0 ? Colors.red : Colors.green,
              ),
            ],
          ),
          
          const SizedBox(height: 24),

          // --- Top Spending Drivers ---
          Text(
            "Top Drivers (Last 30 Days)",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_topCategories.isEmpty)
            const Text("No spending in the last 30 days.", style: TextStyle(color: Colors.grey))
          else
            Card(
              elevation: 0,
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: _topCategories.map((entry) {
                    return _buildCategoryListItem(
                      entry.key, 
                      entry.value,
                      _chartColors[_topCategories.indexOf(entry) % _chartColors.length],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Helper for showing errors or "not enough data"
  Widget _buildMessageUI(String message) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// A color-coded card comparing forecast to income
 Widget _buildIncomeAlertCard() {
    if (_manualIncome <= 0) {
      // This card to set income (unchanged in content, just style)
      return Card(
        elevation: 4, // Added shadow
        color: Colors.white, // White background
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), // Match other cards
        ),
        margin: const EdgeInsets.only(bottom: 12), // Add some bottom margin
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Set Your Income", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.blue.shade900, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("Go to the Dashboard and tap the ✏️ on the 'Total Income' card to set your monthly income for a better forecast comparison.", style: TextStyle(color: Colors.grey[800])),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    final forecastCount = _forecastSpots.length > 1 ? _forecastSpots.length - 1 : 3;
    final avgMonthlyForecast = _totalForecastedSpend / forecastCount; 
    const color = Color.fromARGB(255, 0, 101, 179);
    const icon = Icons.query_stats;
    const title = "Avg. Monthly Forecast";
    final message = "₹${avgMonthlyForecast.toStringAsFixed(0)} / month";

    // This card for average monthly forecast
    return Card(
      elevation: 4, // Added shadow
      color: Colors.white, // White background
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12), // Add some bottom margin
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(icon, color: color, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 13, color: Color.fromARGB(255, 0, 0, 0)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Helper widget for the small stat cards
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 4, // Added shadow
        color: Colors.white, // White background
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(color: Color.fromARGB(255, 0, 0, 0), fontSize: 13)),
              Text(
                value, 
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A list of colors for the pie chart sections
  final List<Color> _chartColors = [
    Colors.blue.shade400,
    Colors.red.shade400,
    Colors.green.shade400,
    Colors.orange.shade400,
    Colors.purple.shade400,
  ];

  /// Helper widget for the category list items
  Widget _buildCategoryListItem(String category, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration( color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(category, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(
            "₹${amount.toStringAsFixed(2)}",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// --- SMS TRANSACTION SCREEN (MERGED FROM read_sms.dart) ---
class SmsTransactionScreen extends StatefulWidget {
  const SmsTransactionScreen({super.key});

  @override
  State<SmsTransactionScreen> createState() => _SmsTransactionScreenState();
}

class _SmsTransactionScreenState extends State<SmsTransactionScreen> {
  final Telephony telephony = Telephony.instance;
  List<SmsMessage> _messages = []; // List to hold fetched SMS
  bool _permissionGranted = false;
  bool _isLoading = false; // To show loading indicator

  @override
  void initState() {
    super.initState();
    _checkAndFetchSms(); // Request permission and fetch on init
  }

  Future<void> _checkAndFetchSms() async {
    final status = await Permission.sms.request();
    print("SMS Permission Status: $status");

    if (mounted) {
      setState(() {
        _permissionGranted = status.isGranted;
      });

      if (_permissionGranted) {
        _fetchInboxSms();
      } else {
        _showPermissionDeniedDialog();
      }
    }
  }

  Future<void> _fetchInboxSms() async {
    if (!_permissionGranted) {
       if(mounted){ ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SMS permission required to fetch messages.')),
       );}
       return;
    }

    if(mounted) setState(() => _isLoading = true);

    print("Querying SMS Inbox...");
    try {
      List<SmsMessage> messages = await telephony.getInboxSms(
          columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE_SENT],
          // filter: SmsFilter.where(SmsColumn.ADDRESS).like("VM-%").or(SmsColumn.ADDRESS).like("AX-%"),
          sortOrder: [OrderBy(SmsColumn.DATE_SENT, sort: Sort.DESC)]
      );

      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
        print("Fetched ${_messages.length} messages.");
      }
    } catch (e) {
       print("Error querying SMS: $e");
       if (mounted) {
         setState(() => _isLoading = false);
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error fetching SMS: $e')),
         );
       }
    }
  }

  void _addExpenseFromSelectedSms(SmsMessage message) {
    if (message.body == null || message.body!.isEmpty) {
       if(mounted){ ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected SMS has no body.')),
       );}
       return;
    }

    SmsTransaction? transaction = parseIndianBankSms(message.body!);

    if (transaction == null) {
      if(mounted){ ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not parse transaction details from this SMS.')),
      );}
      return;
    }

    if (transaction.transactionType != 'Debit') {
      if(mounted){ ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only Debit transactions can be added as expenses.')),
      );}
      return;
    }

    // ---
    // CORRECTED DATE PARSING BLOCK
    // ---
    DateTime expenseDate = DateTime.now();
    try {
      // Use the same robust parsing as the OCR screen
      List<String> formats = ['dd/MM/yyyy', 'dd-MM-yyyy', 'dd.MM.yyyy', 'yyyy/MM/dd', 'yyyy-MM-dd', 'yyyy.MM.dd', 'MM/dd/yyyy'];
      for (var format in formats) {
        try {
          // Use parseLoose to be flexible with format
          expenseDate = DateFormat(format).parseLoose(transaction.date);
          
          // Now, try to add time if it exists
          if (transaction.time != 'N/A') {
            final timeParts = transaction.time.split(':');
            int hour = int.tryParse(timeParts[0]) ?? 0;
            int minute = (timeParts.length > 1) ? int.tryParse(timeParts[1]) ?? 0 : 0;
            // Only add if time parts are valid
            if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
              expenseDate = expenseDate.add(Duration(hours: hour, minutes: minute));
            }
          }
          break; // Stop on first successful parse
        } catch (_) {/* Try next format */}
      }
    } catch (e) {
      print("Error parsing date/time from SMS transaction: ${transaction.date} ${transaction.time} - $e");
      // Fallback to DateTime.now() is already handled
    }
    // ---
    // END OF CORRECTION
    // ---

    String category = categorizeMerchant(transaction.merchantName); // Use GLOBAL function
    final List<String> expenseCategories = ['Entertainment', 'Food', 'Groceries', 'Healthcare', 'Shopping', 'Travel', 'Utilities', 'Others'];
    if (!expenseCategories.contains(category) || category == 'Income' || category == 'Unknown'){ category = 'Others'; }

    final newExpense = Expense(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // Added ID
      title: transaction.merchantName == 'N/A' ? 'SMS Debit (${transaction.bankName})' : transaction.merchantName,
      amount: transaction.amount,
      category: category,
      date: expenseDate,
      description: 'Added from SMS\nSender: ${message.address}\nBody: ${message.body}',
      transactionType: 'Debit', // SMS added expenses are always Debits
    );
    ExpenseService.addExpense(newExpense);

    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added expense: ₹${newExpense.amount.toStringAsFixed(2)} from ${newExpense.title}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

   void _showPermissionDeniedDialog() {
     if (!mounted) return;
     showDialog(
       context: context,
       builder: (BuildContext context) => AlertDialog(
         title: const Text('Permission Denied'),
         content: const Text('SMS permission is required to read messages. Please grant the permission in app settings to use this feature.'),
         actions: <Widget>[
           TextButton(
             child: const Text('Open Settings'),
             onPressed: () {
               openAppSettings();
               Navigator.of(context).pop();
             },
           ),
            TextButton(
             child: const Text('OK'),
             onPressed: () => Navigator.of(context).pop(),
           ),
         ],
       ),
     );
   }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select SMS to Add Expense'),
        automaticallyImplyLeading: false,
         actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh SMS List',
              onPressed: _permissionGranted ? _fetchInboxSms : null,
            ),
         ],
      ),
      body: !_permissionGranted
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.sms_failed_outlined, size: 60, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'SMS Permission Required',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please grant SMS permission to select messages.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _checkAndFetchSms,
                      child: const Text('Grant SMS Permission'),
                    ),
                  ],
                ),
              ),
            )
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text(
                          'No SMS messages found in Inbox.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                         ),
                       ),
                     )
                  : ListView.builder(
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final dateSent = message.dateSent != null
                            ? DateTime.fromMillisecondsSinceEpoch(message.dateSent!)
                            : null;
                        final formattedDate = dateSent != null
                            ? DateFormat('dd MMM yyyy, hh:mm a').format(dateSent)
                            : 'Unknown Date';

                        final previewTransaction = parseIndianBankSms(message.body ?? '');
                        bool isDebit = previewTransaction?.transactionType == 'Debit';


                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isDebit ? Colors.orange.shade100 : Colors.grey.shade200,
                            child: Icon(
                              isDebit ? Icons.arrow_upward : Icons.mail_outline,
                              color: isDebit ? Colors.orange.shade800 : Colors.grey.shade700,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            message.address ?? 'Unknown Sender',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(
                            message.body ?? 'No Content',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                             style: const TextStyle(fontSize: 13),
                          ),
                           trailing: Text(
                             formattedDate,
                             style: const TextStyle(fontSize: 10, color: Colors.grey),
                           ),
                          onTap: () {
                            _addExpenseFromSelectedSms(message);
                          },
                           tileColor: isDebit ? Colors.orange.withOpacity(0.05) : null,
                        );
                      },
                    ),
    );
  }
}
// --- END SMS TRANSACTION SCREEN ---


// --- FINANCIAL ADVISOR SCREEN ---
class FinancialAdvisorScreen extends StatelessWidget { const FinancialAdvisorScreen({super.key}); @override Widget build(BuildContext context) { return Scaffold( appBar: AppBar( title: const Text('Financial Advisor'), automaticallyImplyLeading: false,), body: const Center( child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.lightbulb_outline, size: 80, color: Colors.grey), SizedBox(height: 20), Text( 'Coming Soon!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), SizedBox(height: 10), Padding( padding: EdgeInsets.symmetric(horizontal: 40.0), child: Text( 'Personalized financial advice and tips based on your spending will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),), ], ), ), ); } }

// --- ALL TRANSACTIONS SCREEN ---
class AllTransactionsScreen extends StatefulWidget { const AllTransactionsScreen({super.key}); @override State<AllTransactionsScreen> createState() => _AllTransactionsScreenState(); }
class _AllTransactionsScreenState extends State<AllTransactionsScreen> { 
  List<Expense> _allExpenses = []; 
  
  @override 
  void initState() { 
    super.initState(); 
    _loadAllTransactions(); 
    ExpenseService.dataChanged.addListener(_loadAllTransactions);
  } 
  
  @override
  void dispose() {
    ExpenseService.dataChanged.removeListener(_loadAllTransactions);
    super.dispose();
  }

  void _loadAllTransactions() { 
    final manualExpenses = ExpenseService.getExpenses(); 
    if (mounted) { 
      setState(() { 
        _allExpenses = manualExpenses; 
      }); 
    } 
  } 
  
  @override 
  Widget build(BuildContext context) { 
    return Scaffold( 
      appBar: AppBar( title: const Text('All Transactions')), 
      body: _allExpenses.isEmpty 
          ? const Center( child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.history_toggle_off, size: 60, color: Colors.grey), SizedBox(height: 16), Text( 'No transactions recorded yet.', style: TextStyle(fontSize: 16, color: Colors.grey),), ], ), ) 
          : ListView.separated( 
              padding: const EdgeInsets.all(8.0), 
              itemCount: _allExpenses.length, 
              itemBuilder: (context, index) {
                // Use the reusable tile
                return TransactionListTile(
                  expense: _allExpenses[index], 
                  onRefresh: _loadAllTransactions
                ); 
              }, 
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16), 
            ), 
    ); 
  } 
}
// --- END ALL TRANSACTIONS SCREEN ---

// --- REUSABLE WIDGET ---
class TransactionListTile extends StatelessWidget {
  final Expense expense;
  final VoidCallback onRefresh;

  const TransactionListTile({
    super.key,
    required this.expense,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final bool isCredit = expense.transactionType == 'Credit';
    final IconData leadingIcon = isCredit ? Icons.arrow_downward : Icons.arrow_upward;
    final Color leadingColor = isCredit ? Colors.green : Colors.red;
    final Color amountColor = isCredit ? Colors.green.shade700 : Colors.red.shade700;
    
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddExpenseScreen(existingExpense: expense),
          ),
        ).then((_) => onRefresh()); // Call the refresh callback
      },
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: leadingColor,
          child: Icon(leadingIcon, color: Colors.white, size: 18),
        ),
        title: Text(
          '${expense.title} (${expense.category})',
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          DateFormat('dd MMM yyyy').format(expense.date),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Text(
          '${isCredit ? '+' : '-'}₹${expense.amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: amountColor,
          ),
        ),
      ),
    );
  }
}
// --- END REUSABLE WIDGET ---