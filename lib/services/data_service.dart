import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class DataService {
  // 1. LOCAL DATA FETCHING
  // This loads the JSON directly from your 'assets/' folder.
  Future<List<dynamic>> fetchLocalData(String assetPath) async {
    try {
      final String response = await rootBundle.loadString(assetPath);
      final data = await json.decode(response);
      return data['items']; // Assuming your JSON has an 'items' key
    } catch (e) {
      print("Error loading local data: $e");
      return [];
    }
  }

  // 2. HYBRID LOGIC 
  // This demonstrates how you'll eventually switch to the cloud.
  Future<List<dynamic>> getSigns() async {
    bool hasInternet = await _checkInternetConnection();

    if (hasInternet) {
      // Logic for Phase 3: Fetch from Firebase/Supabase
      return await _fetchCloudData();
    } else {
      // Logic for Phase 1 & 2: Fallback to local
      return await fetchLocalData('assets/data/signs.json');
    }
  }

  Future<bool> _checkInternetConnection() async {
    // You can use a package like 'connectivity_plus' here
    return false; // Return false for now to test your local assets
  }

  Future<List<dynamic>> _fetchCloudData() async {
    // Placeholder for your future cloud API calls
    return [];
  }
}