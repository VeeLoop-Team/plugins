// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase_connection.dart';
import 'package:in_app_purchase/store_kit_wrappers.dart';

void main() {
  runApp(MyApp());
}

const bool Auto_Consume = false;

const List<String> _kProductIds = <String>[
  'consumable',
  'upgrade',
  'subscription'
];

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<List<PurchaseDetails>> _subscription;
  @override
  void initState() {
    Stream purchaseUpdated =
        InAppPurchaseConnection.instance.purchaseUpdatedStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      purchaseDetailsList.forEach((PurchaseDetails purchaseDetails) {
        print('purchase updated product ID: (${purchaseDetails.productID})');
        print('purchase updated purchase ID: (${purchaseDetails.purchaseID})');
        print('purchase updated status: ({${purchaseDetails.status})');
        if (purchaseDetails.status == PurchaseStatus.pending) {
          showPendingUI();
        } else {
          if (purchaseDetails.status == PurchaseStatus.error) {
            handleError(purchaseDetails.error);
          } else if (purchaseDetails.status == PurchaseStatus.purchased) {
            deliverProduct(purchaseDetails);
          }
          if (Platform.isIOS) {
            InAppPurchaseConnection.instance.completePurchase(purchaseDetails);
          } else if (Platform.isAndroid) {
            if (!Auto_Consume && purchaseDetails.productID == 'consumable') {
              InAppPurchaseConnection.instance.consumePurchase(purchaseDetails);
            }
          }
        }
      });
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      print('Error on listening to purchaseUpdatesStream $error');
    });
    super.initState();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    InAppPurchaseConnection.instance.updateDownloads(downloads: [
      SKDownloadWrapper(
        contentIdentifier: 'id',
        state: SKDownloadState.failed,
        contentLength: 32,
        contentURL: 'https://download.com',
        contentVersion: '0.0.1',
        transactionID: 'tranID',
        progress: 0.6,
        timeRemaining: 1231231,
        downloadTimeUnknown: false,
        error: null,
      )
    ], operation: SKDownloadOperation.start);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('IAP Example'),
        ),
        body: ListView(
          children: [
            FutureBuilder(
              future: _buildConnectionCheckTile(),
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                if (snapshot.error != null) {
                  return buildListCard(ListTile(
                      title: Text(
                          'Error connecting: ' + snapshot.error.toString())));
                } else if (!snapshot.hasData) {
                  return Card(
                      child:
                          ListTile(title: const Text('Trying to connect...')));
                }
                return snapshot.data;
              },
            ),
            FutureBuilder(
              future: _buildProductList(),
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                if (snapshot.error != null) {
                  print(snapshot.error);
                  return Center(
                    child: buildListCard(
                        ListTile(title: Text('Error fetching products'))),
                  );
                } else if (!snapshot.hasData) {
                  return Card(
                      child: (ListTile(
                          leading: CircularProgressIndicator(),
                          title: Text('Fetching products...'))));
                }
                return snapshot.data;
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Card> _buildConnectionCheckTile() async {
    final bool available = await InAppPurchaseConnection.instance.isAvailable();
    final Widget storeHeader = ListTile(
      leading: Icon(available ? Icons.check : Icons.block,
          color: available ? Colors.green : ThemeData.light().errorColor),
      title: Text(
          'The store is ' + (available ? 'available' : 'unavailable') + '.'),
    );
    final List<Widget> children = <Widget>[storeHeader];

    if (!available) {
      children.addAll([
        Divider(),
        ListTile(
          title: Text('Not connected',
              style: TextStyle(color: ThemeData.light().errorColor)),
          subtitle: const Text(
              'Unable to connect to the payments processor. Has this app been configured correctly? See the example README for instructions.'),
        ),
      ]);
    }
    return Card(child: Column(children: children));
  }

  Future<Card> _buildProductList() async {
    InAppPurchaseConnection connection = InAppPurchaseConnection.instance;
    final bool available = await connection.isAvailable();
    if (!available) {
      return Card();
    }
    final ListTile productHeader = ListTile(
        title: Text('Products for Sale',
            style: Theme.of(context).textTheme.headline));
    ProductDetailsResponse response =
        await connection.queryProductDetails(_kProductIds.toSet());
    List<ListTile> productList = <ListTile>[];
    if (!response.notFoundIDs.isEmpty) {
      productList.add(ListTile(
          title: Text('[${response.notFoundIDs.join(", ")}] not found',
              style: TextStyle(color: ThemeData.light().errorColor)),
          subtitle: Text(
              'This app needs special configuration to run. Please see example/README.md for instructions.')));
    }

    // This loading previous purchases code is just a demo. Please do not use this as it is.
    // In your app you should always verify the purchase data using the `verificationData` inside the [PurchaseDetails] object before trusting it.
    // We recommend that you use your own server to verity the purchase data.
    Map<String, PurchaseDetails> purchases = Map.fromEntries(
        ((await connection.queryPastPurchases()).pastPurchases)
            .map((PurchaseDetails purchase) {
      print('restored productID: ${purchase.productID}');
      print('restored purchaseID: ${purchase.purchaseID}');
      if (purchase.status == PurchaseStatus.pending) {
        print('restored pending purchased ${purchase.productID}');
      } else {
        if (Platform.isIOS) {
          InAppPurchaseConnection.instance.completePurchase(purchase);
        }
        if (Platform.isAndroid && purchase.productID == 'consumable') {
          print('consume restored');
          InAppPurchaseConnection.instance.consumePurchase(purchase);
        }
      }
      return MapEntry<String, PurchaseDetails>(purchase.productID, purchase);
    }));
    productList.addAll(response.productDetails.map(
      (ProductDetails productDetails) {
        PurchaseDetails previousPurchase = purchases[productDetails.id];
        return ListTile(
          title: Text(
            productDetails.title,
          ),
          subtitle: Text(
            productDetails.description,
          ),
          trailing: previousPurchase != null
              ? Icon(Icons.check)
              : Text(productDetails.price),
          onTap: () {
            PurchaseParam purchaseParam = PurchaseParam(
                productDetails: productDetails,
                applicationUserName: null,
                sandboxTesting: true);
            if (productDetails.id == 'consumable') {
              connection.buyConsumable(
                  purchaseParam: purchaseParam,
                  autoConsume: Auto_Consume || Platform.isIOS);
            } else {
              connection.buyNonConsumable(purchaseParam: purchaseParam);
            }
          },
        );
      },
    ));

    return Card(
        child:
            Column(children: <Widget>[productHeader, Divider()] + productList));
  }

  void showPendingUI() {
    print('pending UI showed');
  }

  void deliverProduct(PurchaseDetails purchaseDetails) {
    // IMPORTANT!! Always verify a purchase purchase details before deliver the product.
    print('product delivered');
  }

  void handleError(PurchaseError error) {
    print('purchase error ${error.message}');
  }

  static ListTile buildListCard(ListTile innerTile) =>
      ListTile(title: Card(child: innerTile));
}
