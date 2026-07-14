import 'package:cloud_firestore/cloud_firestore.dart';

class SignService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Fetch a specific sign by its name (e.g., "A", "B", "1")
  Future<Map<String, dynamic>?> getSignMetadata(String signName) async {
    try {
      DocumentSnapshot doc = await _db.collection('signs').doc(signName).get();
      
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      } else {
        print('Sign not found in database.');
        return null;
      }
    } catch (e) {
      print('Error fetching sign: $e');
      return null;
    }
  }

  // Fetch all signs for a specific category (e.g., 'alphabet' or 'numbers')
  Future<List<Map<String, dynamic>>> getSignsByCategory(String category) async {
    try {
      QuerySnapshot querySnapshot = await _db
          .collection('signs')
          .where('category', isEqualTo: category)
          .get();

      return querySnapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('Error fetching category: $e');
      return [];
    }
  }
}