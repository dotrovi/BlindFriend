import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final FlutterTts _tts = FlutterTts();
  final MobileScannerController _scannerController = MobileScannerController();
  
  bool _isLoading = false;
  bool _isScanning = true;
  ProductInfo? _scannedProduct;
  String? _errorMessage;
  List<ProductInfo> _recentScans = [];

  @override
  void initState() {
    super.initState();
    _initTts();
    _speak('Barcode scanner opened. Point your camera at a product barcode.');
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
    } catch (_) {
      await _tts.setLanguage('en');
    }
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  void _speak(String message) {
    _tts.speak(message);
    print('🔊 TTS: $message');
  }

  Future<void> _handleBarcodeDetected(BarcodeCapture capture) async {
    if (!_isScanning || _isLoading) return;
    
    final barcode = capture.barcodes.first;
    final rawValue = barcode.rawValue;
    
    if (rawValue != null && rawValue.isNotEmpty) {
      setState(() {
        _isScanning = false;
        _isLoading = true;
      });
      
      await _scannerController.stop();
      _speak('Barcode detected: $rawValue. Looking up product information.');
      
      final product = await _fetchProductInfo(rawValue);
      
      setState(() {
        _isLoading = false;
      });
      
      if (product != null) {
        setState(() {
          _scannedProduct = product;
          _recentScans.insert(0, product);
          if (_recentScans.length > 10) _recentScans.removeLast();
        });
        
        _speak(_getProductDescription(product));
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found: ${product.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'Product not found. Try scanning again.';
        });
        _speak('Product not found in database. Please try another barcode.');
        
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _isScanning = true;
              _errorMessage = null;
            });
            _scannerController.start();
            _speak('Ready to scan another barcode.');
          }
        });
      }
    }
  }

  Future<ProductInfo?> _fetchProductInfo(String barcode) async {
    try {
      final response = await http.get(
        Uri.parse('https://world.openfoodfacts.org/api/v0/product/$barcode.json'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 1) {
          final product = data['product'];
          return ProductInfo(
            barcode: barcode,
            name: product['product_name'] ?? 'Unknown product',
            brand: product['brands'] ?? 'Unknown brand',
            ingredients: product['ingredients_text'] ?? 'Ingredients not available',
            quantity: product['quantity'] ?? '',
            imageUrl: product['image_url'] ?? '',
            nutrition: _extractNutrition(product),
            allergens: product['allergens'] ?? 'Not specified',
          );
        }
      }
      return null;
    } catch (e) {
      print('Error fetching product: $e');
      return null;
    }
  }

  String _extractNutrition(Map<String, dynamic> product) {
    final nutriments = product['nutriments'];
    if (nutriments != null) {
      final calories = nutriments['energy-kcal'] ?? nutriments['energy'] ?? '';
      if (calories.toString().isNotEmpty) {
        return 'Calories: ${calories.toString()} per serving';
      }
    }
    return 'Nutrition information not available';
  }

  String _getProductDescription(ProductInfo product) {
    return 'Product found: ${product.name}. '
        'Brand: ${product.brand}. '
        '${product.quantity.isNotEmpty ? 'Size: ${product.quantity}. ' : ''}'
        '${product.allergens != 'Not specified' ? 'Allergens: ${product.allergens}. ' : ''}'
        '${product.ingredients.isNotEmpty ? 'Ingredients: ${product.ingredients}' : ''}';
  }

  void _rescan() {
    setState(() {
      _isScanning = true;
      _scannedProduct = null;
      _errorMessage = null;
    });
    _scannerController.start();
    _speak('Ready to scan another barcode.');
  }

  void _readProductDetails() {
    if (_scannedProduct != null) {
      _speak(_getProductDescription(_scannedProduct!));
    }
  }

  void _readIngredients() {
    if (_scannedProduct != null && _scannedProduct!.ingredients.isNotEmpty) {
      _speak('Ingredients: ${_scannedProduct!.ingredients}');
    }
  }

  void _readAllergens() {
    if (_scannedProduct != null && _scannedProduct!.allergens != 'Not specified') {
      _speak('Allergen warning: ${_scannedProduct!.allergens}');
    } else {
      _speak('No allergens information available for this product.');
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.blue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            _speak('Closing scanner.');
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Shopping Helper',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.switch_camera, color: Colors.white),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Scanner Area
          if (_isScanning)
            Container(
              height: 300,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: MobileScanner(
                      controller: _scannerController,
                      onDetect: _handleBarcodeDetected,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green, width: 3),
                    ),
                    margin: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.crop_free, size: 50, color: Colors.green),
                          const SizedBox(height: 8),
                          Text(
                            'Align barcode here',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Loading Indicator
          if (_isLoading)
            Container(
              height: 300,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
                ],
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.blue),
                    SizedBox(height: 16),
                    Text('Looking up product...', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
          
          // Scan Button (when not scanning and no product)
          if (!_isScanning && !_isLoading && _scannedProduct == null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.qr_code_scanner, size: 60, color: Colors.blue),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage ?? 'No product scanned',
                    style: TextStyle(
                      fontSize: 16,
                      color: _errorMessage != null ? Colors.red : Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _rescan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan Another Barcode'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Product Details Section
          if (_scannedProduct != null)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Product Name and Audio Button
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _scannedProduct!.name,
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.volume_up, color: Colors.blue, size: 28),
                                onPressed: _readProductDetails,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Brand: ${_scannedProduct!.brand}',
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          if (_scannedProduct!.quantity.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Size: ${_scannedProduct!.quantity}',
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                          ],
                          const SizedBox(height: 8),
                          const Divider(),
                          const SizedBox(height: 8),
                          
                          // INGREDIENTS SECTION
                          const Text(
                            'Ingredients:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _scannedProduct!.ingredients,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          
                          // Allergen Warning
                          if (_scannedProduct!.allergens != 'Not specified')
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Allergen Warning',
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                                        ),
                                        Text(_scannedProduct!.allergens, style: const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.volume_up, size: 20),
                                    onPressed: _readAllergens,
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          
                          // Nutrition
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.food_bank, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _scannedProduct!.nutrition,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.volume_up, size: 20),
                                  onPressed: () => _speak(_scannedProduct!.nutrition),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          // Barcode
                          Row(
                            children: [
                              const Icon(Icons.qr_code, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text(
                                'Barcode: ${_scannedProduct!.barcode}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _readIngredients,
                                  icon: const Icon(Icons.list_alt),
                                  label: const Text('Ingredients'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _rescan,
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: const Text('Scan Again'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Recent Scans Section
                    if (_recentScans.length > 1)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Recent Scans',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            ..._recentScans.skip(1).take(5).map((product) => ListTile(
                              leading: const Icon(Icons.qr_code, color: Colors.blue),
                              title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(product.brand),
                              trailing: IconButton(
                                icon: const Icon(Icons.volume_up, size: 20),
                                onPressed: () => _speak(_getProductDescription(product)),
                              ),
                              onTap: () {
                                setState(() {
                                  _scannedProduct = product;
                                });
                                _speak(_getProductDescription(product));
                              },
                            )),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ProductInfo {
  final String barcode;
  final String name;
  final String brand;
  final String ingredients;
  final String quantity;
  final String imageUrl;
  final String nutrition;
  final String allergens;

  ProductInfo({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.ingredients,
    required this.quantity,
    required this.imageUrl,
    required this.nutrition,
    required this.allergens,
  });
}