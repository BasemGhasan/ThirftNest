// lib/courierLogic/delivery_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'delivery_model.dart';
import '../SellerLogic/item_crud.dart';

class DeliveryService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'deliveryRequests';

  /// Get all available delivery requests (status = pending)
  static Stream<List<DeliveryRequest>> getAvailableDeliveries() {
    return _firestore
        .collection(_collection)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.map((doc) => DeliveryRequest.fromDoc(doc)).toList();
          // Sort in Dart instead of Firestore to avoid index requirements
          docs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return docs;
        });
  }

  /// Get courier's accepted deliveries
  static Stream<List<DeliveryRequest>> getCourierDeliveries(String courierId) {
    return _firestore
        .collection(_collection)
        .where('courierId', isEqualTo: courierId)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs
              .map((doc) => DeliveryRequest.fromDoc(doc))
              .where((delivery) => 
                  delivery.status == DeliveryStatus.accepted || 
                  delivery.status == DeliveryStatus.inTransit)
              .toList();
          // Sort in Dart
          docs.sort((a, b) => (b.acceptedAt ?? DateTime(1970)).compareTo(a.acceptedAt ?? DateTime(1970)));
          return docs;
        });
  }

  /// Accept a delivery request
  static Future<void> acceptDelivery(
    String deliveryId,
    String courierId,
    String courierName,
  ) async {
    await _firestore.collection(_collection).doc(deliveryId).update({
      'courierId': courierId,
      'courierName': courierName,
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update delivery status to in-transit
  static Future<void> startDelivery(String deliveryId) async {
    await _firestore.collection(_collection).doc(deliveryId).update({
      'status': 'inTransit',
      'startedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Complete delivery
  static Future<void> completeDelivery(String deliveryId) async {
    // First, get the delivery document to retrieve the itemId
    DocumentSnapshot deliveryDoc = await _firestore.collection(_collection).doc(deliveryId).get();
    if (!deliveryDoc.exists) {
      throw Exception("Delivery request with ID $deliveryId not found.");
    }
    Map<String, dynamic>? deliveryData = deliveryDoc.data() as Map<String, dynamic>?;
    String? itemId = deliveryData?['itemId'] as String?;

    if (itemId == null || itemId.isEmpty) {
      // Consider how to handle cases where itemId is missing.
      // For now, we'll log and proceed with delivery completion.
      print('Warning: itemId not found in delivery request $deliveryId. Cannot update item sellingStage.');
    }

    // Update the delivery request status
    await _firestore.collection(_collection).doc(deliveryId).update({
      'status': 'delivered',
      'deliveredAt': FieldValue.serverTimestamp(),
    });

    // If itemId is available, update the item's sellingStage to 'Sold'
    if (itemId != null && itemId.isNotEmpty) {
      try {
        await updateItem(itemId: itemId, sellingStage: 'Sold');
      } catch (e) {
        // Log or handle the error if updating the item fails
        print('Error updating sellingStage for item $itemId: $e');
        // Depending on requirements, you might want to throw this error
        // or handle it without failing the entire completeDelivery operation.
      }
    }
  }

  /// Cancel delivery (return to pending status)
  static Future<void> cancelDelivery(String deliveryId) async {
    await _firestore.collection(_collection).doc(deliveryId).update({
      'courierId': null,
      'courierName': null,
      'status': 'pending',
      'acceptedAt': null,
    });
  }

  /// Create a new delivery request (called when buyer purchases an item)
  static Future<void> createDeliveryRequest({
    required String itemId,
    required String itemTitle,
    required String sellerId,
    required String sellerName,
    required String sellerPhone,
    required String buyerId,
    required String buyerName,
    required String buyerPhone,
    required String pickupAddress,
    required String deliveryAddress,
    double? pickupLatitude,
    double? pickupLongitude,
    double? deliveryLatitude,
    double? deliveryLongitude,
    String? specialInstructions,
  }) async {
    final deliveryRequest = DeliveryRequest(
      id: '', // Will be auto-generated
      itemId: itemId,
      itemTitle: itemTitle,
      sellerId: sellerId,
      sellerName: sellerName,
      sellerPhone: sellerPhone,
      buyerId: buyerId,
      buyerName: buyerName,
      buyerPhone: buyerPhone,
      pickupAddress: pickupAddress,
      deliveryAddress: deliveryAddress,
      status: DeliveryStatus.pending,
      createdAt: DateTime.now(),
      pickupLatitude: pickupLatitude,
      pickupLongitude: pickupLongitude,
      deliveryLatitude: deliveryLatitude,
      deliveryLongitude: deliveryLongitude,
      specialInstructions: specialInstructions,
    );

    await _firestore.collection(_collection).add(deliveryRequest.toMap());
  }

  /// Get delivery request by ID
  static Future<DeliveryRequest?> getDeliveryById(String deliveryId) async {
    final doc = await _firestore.collection(_collection).doc(deliveryId).get();
    if (doc.exists) {
      return DeliveryRequest.fromDoc(doc);
    }
    return null;
  }

  /// Get courier's delivery history
  static Future<List<DeliveryRequest>> getCourierHistory(String courierId) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('courierId', isEqualTo: courierId)
        .where('status', whereIn: ['delivered', 'cancelled'])
        .orderBy('deliveredAt', descending: true)
        .limit(50)
        .get();

    return snapshot.docs.map((doc) => DeliveryRequest.fromDoc(doc)).toList();
  }
}