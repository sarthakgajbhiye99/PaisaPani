import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// --- IMPROVED EXTRACTION LOGIC ---

/// Extracts the shop name, assuming it's one of the first few prominent, capitalized lines.
String extractShopName(RecognizedText recognizedText) {
  final potentialNames = recognizedText.blocks
      .take(5)
      .map((block) => block.text.trim())
      .where((text) => text.isNotEmpty)
      .toList();

  for (String name in potentialNames) {
    if (name.toUpperCase() == name && name.length > 3) {
      return name;
    }
  }
  return potentialNames.isNotEmpty ? potentialNames.first : 'N/A';
}

// --- THIS IS THE FIXED FUNCTION ---
/// Extracts the date using a comprehensive regex that handles multiple formats.
String extractDate(String fullText) {
  // This regex is designed to find a wide variety of common date formats.
  // It's case-insensitive to catch "Aug", "aug", or "AUG".
  final dateRegex = RegExp(
      // Handles formats like 08/26/2025, 26-08-2025, 2025.08.26
      r'(\d{1,4}[-./]\d{1,2}[-./]\d{1,4})|' r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4})|' +

      // Handles formats like "26 Aug 2025" or "26-AUG-2025"
      r'(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?,?\s+\d{2,4})',
      
      caseSensitive: false,
  );

  final match = dateRegex.firstMatch(fullText);
  
  // Return the found date, or 'N/A' if no date is found.
  return match?.group(0)?.replaceAll(',', '') ?? 'N/A';
}


/// Extracts the total amount by finding the largest numerical value associated with a "total" keyword.
String extractTotalAmount(String fullText) {
  double maxAmount = -1.0;
  final lines = fullText.split('\n');
  final amountRegex = RegExp(r'[\$€£]?\s?(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2}))');
  final keywords = ['total', 'amount', 'balance', 'due', 'grand total'];
  
  for (final line in lines) {
    final lowerLine = line.toLowerCase();
    if (keywords.any((kw) => lowerLine.contains(kw))) {
      final match = amountRegex.firstMatch(line);
      if (match != null) {
        final potentialAmount = double.tryParse(match.group(1)!.replaceAll(',', ''));
        if (potentialAmount != null && potentialAmount > maxAmount) {
          maxAmount = potentialAmount;
        }
      }
    }
  }

  if (maxAmount == -1.0) {
    final allMatches = amountRegex.allMatches(fullText);
    for (final match in allMatches) {
        final potentialAmount = double.tryParse(match.group(1)!.replaceAll(',', ''));
        if (potentialAmount != null && potentialAmount > maxAmount) {
          maxAmount = potentialAmount;
        }
    }
  }

  return maxAmount != -1.0 ? maxAmount.toStringAsFixed(2) : 'N/A';
}

// --- NO CHANGES NEEDED BELOW THIS LINE ---

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Personal Finance Management',
      theme: ThemeData(
        primarySwatch: Colors.lightGreen,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    DashboardScreen(),
    ReceiptScannerScreen(),
    BudgetForecastScreen(),
    FinancialAdvisorScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Finance App'),
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt),
            label: 'Scan Receipt',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'Forecast',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb_outline),
            label: 'Advice',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showAddExpenseModal(context),
              icon: const Icon(Icons.add),
              label: const Text(
                'Add expense',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color.fromARGB(255, 141, 214, 248),
            )
          : null,
    );
  }

  void _showAddExpenseModal(BuildContext context) {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController amountController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Expense',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    final String title = titleController.text.trim();
                    final String amountText = amountController.text.trim();
                    if (title.isEmpty || amountText.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter title and amount')),
                      );
                      return;
                    }
                    final double? amount = double.tryParse(amountText.replaceAll(',', ''));
                    if (amount == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid amount')),
                      );
                      return;
                    }
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added "$title" - \$${amount.toStringAsFixed(2)}')),
                    );
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Welcome, User!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          Text(
            'Your Financial Summary',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Expenses this month:'),
                      Text('\$1,250.00', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Budget for this month:'),
                      Text('\$2,000.00', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Recent Transactions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Center(
              child: Text('Transaction list will be shown here.'),
            ),
          ),
        ],
      ),
    );
  }
}

class ReceiptScannerScreen extends StatefulWidget {
  const ReceiptScannerScreen({super.key});

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  late final TextRecognizer _textRecognizer;

  XFile? _selectedImage;
  bool _isProcessing = false;
  String? _parsedShop;
  String? _parsedDate;
  String? _parsedTotal;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _isProcessing = true;
      _selectedImage = null;
      _parsedShop = null;
      _parsedDate = null;
      _parsedTotal = null;
      _errorMessage = null;
    });

    try {
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText result = await _textRecognizer.processImage(inputImage);

      final String fullText = result.text;
      final String shop = extractShopName(result);
      final String date = extractDate(fullText);
      final String total = extractTotalAmount(fullText);

      setState(() {
        _selectedImage = image;
        _parsedShop = shop;
        _parsedDate = date;
        _parsedTotal = total;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Failed to process image: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Scan Your Receipts',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick an image or take a photo to extract text.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isProcessing)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_selectedImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_selectedImage!.path),
                  fit: BoxFit.cover,
                  height: 180,
                ),
              ),
            const SizedBox(height: 12),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ),
            if (_errorMessage != null) const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Parsed Details', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Shop: ${_parsedShop ?? 'N/A'}'),
                      Text('Date: ${_parsedDate ?? 'N/A'}'),
                      Text('Total: ${_parsedTotal ?? 'N/A'}'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BudgetForecastScreen extends StatelessWidget {
  const BudgetForecastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.show_chart, size: 100, color: Colors.grey),
          SizedBox(height: 20),
          Text(
            'Budget Forecasting',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              'Predicts future expenses based on your spending habits.',
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 20),
          Text('Forecasting charts will be displayed here.'),
        ],
      ),
    );
  }
}

class FinancialAdvisorScreen extends StatelessWidget {
  const FinancialAdvisorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lightbulb_outline, size: 100, color: Colors.grey),
          SizedBox(height: 20),
          Text(
            'Financial Advisor',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              'Get personalized advice to improve your financial health.',
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 20),
          Text('Personalized suggestions will appear here.'),
        ],
      ),
    );
  }
}