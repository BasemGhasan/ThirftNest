// lib/SellerScreens/SellerManageListing.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import 'ItemPostingOverlay.dart';
import 'ItemEditOverlay.dart';
import '../SellerScreens/ListingTile.dart';
import '../SellerLogic/item_crud.dart';
import '../SellerLogic/seller_listings_service.dart';
import '../SellerLogic/Item_model.dart';
import '../SellerScreens/ItemDetailOverlay.dart';
import '../CommonScreens/ProfileManagementScreen.dart';

class SellerManageListing extends StatefulWidget {
  const SellerManageListing({super.key});

  @override
  State<SellerManageListing> createState() => _SellerManageListingState();
}

class _SellerManageListingState extends State<SellerManageListing> {
  String? _uid;
  late final Future<String> _userNameFuture;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _uid = user.uid;
      SellerListingsService.instance.initForOwner(_uid!);
      _userNameFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid!)
          .get()
          .then((snap) => snap.data()?['fullName'] as String? ?? 'User');
    } else {
      _userNameFuture = Future.value('User');
    }
  }

  Future<void> _openAddSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: ItemPostingOverlay(onClose: () => Navigator.of(context).pop()),
      ),
    );
    if (_uid != null) {
      SellerListingsService.instance.initForOwner(_uid!);
    }
  }

  Future<void> _openEditSheet(ItemModel item) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: ItemEditOverlay(item: item, onClose: () => Navigator.of(context).pop()),
      ),
    );
    if (_uid != null) {
      SellerListingsService.instance.initForOwner(_uid!);
    }
  }

  void _onTabTapped(int idx) => setState(() => _currentIndex = idx);

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Tab 0: Manage Listings (On Sale + On Delivery)
    final manageTab = StreamBuilder<List<ItemModel>>(
      stream: SellerListingsService.instance.listings$,
      builder: (ctx, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items      = snap.data!;
        final onSale     = items.where((it) => it.sellingStage == 'On Sale').toList();
        final onDelivery = items.where((it) => it.sellingStage == 'On Delivery').toList();

        if (onSale.isEmpty && onDelivery.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('lib/images/NoUploadedItems_image.png', height: 200),
                const SizedBox(height: 16),
                const Text(
                  'You haven’t added any items yet.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 80, top: 16),
          children: [
            // ─── On Sale ───────────────────────────────────────
            Row(children: [
              const Expanded(child: Divider(thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('On Sale',
                    style: TextStyle(
                        color: ThriftNestApp.textColor, fontWeight: FontWeight.bold)),
              ),
              const Expanded(child: Divider(thickness: 1)),
            ]),
            const SizedBox(height: 8),

            if (onSale.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No items on sale.')),
              )
            else
              ...onSale.map((item) => ListingTile(
                    id: item.id,
                    title: item.title,
                    price: item.price,
                    imageBytes: item.imageBytes,
                    onEdit: () => _openEditSheet(item),
                    onDelete: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Delete Item?'),
                          content: const Text("This can't be undone."),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(c, true),  child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await deleteItem(item.id);
                        SellerListingsService.instance.initForOwner(_uid!);
                      }
                    },
                  )),

            const SizedBox(height: 24),

            // ─── On Delivery ────────────────────────────────────
            Row(children: [
              const Expanded(child: Divider(thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('On Delivery',
                    style: TextStyle(
                        color: ThriftNestApp.textColor, fontWeight: FontWeight.bold)),
              ),
              const Expanded(child: Divider(thickness: 1)),
            ]),
            const SizedBox(height: 8),

            if (onDelivery.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No items on delivery.')),
              )
            else
              ...onDelivery.map((item) => ListingTile(
                    id: item.id,
                    title: item.title,
                    price: item.price,
                    imageBytes: item.imageBytes,
                    onEdit: null,
                    onDelete: null,
                  )),
          ],
        );
      },
    );

    // Tab 1: Sales History (Sold items)
    final historyTab = StreamBuilder<List<ItemModel>>(
      stream: SellerListingsService.instance.listings$,
      builder: (ctx, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final sold = snap.data!.where((it) => it.sellingStage == 'Sold').toList();

        double totalEarnings = 0.0;
        if (sold.isNotEmpty) {
          for (var item in sold) {
            totalEarnings += item.price; // Assuming item.price is a double
          }
        }

        return Column(
          children: [
            Expanded(
              child: sold.isEmpty
                  ? const Center( // Empty state text ONLY
                      child: Padding(
                        padding: EdgeInsets.all(16.0), // Added padding for the text
                        child: Text(
                          'No items sold yet..', // More descriptive text
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder( // List of sold items
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      itemCount: sold.length,
                      itemBuilder: (ctx, i) {
                        // ... (existing itemBuilder logic for ListingTile)
                        final item = sold[i];
                        return GestureDetector(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => FractionallySizedBox(
                                heightFactor: 0.85,
                                child: ItemDetailOverlay(item: item),
                              ),
                            );
                          },
                          child: ListingTile(
                            id: item.id,
                            title: item.title,
                            price: item.price,
                            imageBytes: item.imageBytes,
                            onEdit: null,
                            onDelete: null,
                          ),
                        );
                      },
                    ),
            ),
            // Conditional Image Display
            // ─── Earnings Visual ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
              children: [
                const Expanded(child: Divider(thickness: 1)),
                Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Earnings',
                  style: TextStyle(
                  color: ThriftNestApp.textColor,
                  fontWeight: FontWeight.bold,
                  ),
                ),
                ),
                const Expanded(child: Divider(thickness: 1)),
              ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: totalEarnings == 0.0
                ? Image.asset(
                  'lib/images/No earnings image.png', // Image for zero earnings
                  height: 250, // Adjust desired height
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 150,
                    color: Colors.grey.shade300,
                    alignment: Alignment.center,
                    child: const Text(
                    'Zero earnings image placeholder\n(zero_earnings_placeholder.png)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                    ),
                  );
                  },
                )
                : Image.asset(
                  'lib/images/Positive earnings image.png', // Image for positive earnings
                  height: 250, // Adjust desired height
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 150,
                    color: Colors.grey.shade300,
                    alignment: Alignment.center,
                    child: const Text(
                    'Earnings image placeholder\n(has_earnings_placeholder.png)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                    ),
                  );
                  },
                ),
            ),
            // Total Earnings Display
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0), // Adjusted padding
              child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                children: [
                  const TextSpan(
                    text: 'Total earnings with ThriftNest: ',
                    style: TextStyle(color: Colors.black),
                  ),
                  TextSpan(
                    text: '\$${totalEarnings.toStringAsFixed(2)}',
                    style: const TextStyle(color: ThriftNestApp.primaryColor),
                  ),
                ],
              ),
            ),
            ),
          ],
        );
      },
    );

    final tabs = [
      manageTab,
      historyTab,
      ProfileManagementScreen(),
    ];

    return Scaffold(
      backgroundColor: ThriftNestApp.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: FutureBuilder<String>(
          future: _userNameFuture,
          builder: (ctx, snap) {
            final name = snap.data ?? 'User';
            return Text('Hi, $name!',
                style: const TextStyle(
                    color: ThriftNestApp.textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold));
          },
        ),
      ),
      body: IndexedStack(index: _currentIndex, children: tabs),
      floatingActionButton: _currentIndex != 2
          ? FloatingActionButton(
              backgroundColor: ThriftNestApp.primaryColor,
              shape: const CircleBorder(),
              onPressed: _openAddSheet,
              child: const Icon(Icons.add, size: 32),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        selectedItemColor: ThriftNestApp.primaryColor,
        unselectedItemColor: ThriftNestApp.textColor,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Listings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
