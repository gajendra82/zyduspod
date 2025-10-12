import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  bool _isConnected = true;

  bool get isConnected => _isConnected;

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    // Check initial connectivity status
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> result) {
        _updateConnectionStatus(result);
      },
    );
  }

  void _updateConnectionStatus(List<ConnectivityResult> result) {
    // Check if any connection is available
    final hasConnection = result.any((connectivityResult) =>
        connectivityResult != ConnectivityResult.none);
    
    if (_isConnected != hasConnection) {
      _isConnected = hasConnection;
      _connectionStatusController.add(_isConnected);
      debugPrint('🌐 Internet Connection: ${_isConnected ? "Connected" : "Disconnected"}');
    }
  }

  /// Check current connectivity status
  Future<bool> checkConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final hasConnection = result.any((connectivityResult) =>
          connectivityResult != ConnectivityResult.none);
      
      _isConnected = hasConnection;
      return hasConnection;
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
      return false;
    }
  }

  /// Dispose connectivity subscription
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectionStatusController.close();
  }
}

