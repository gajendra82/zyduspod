import 'package:flutter/material.dart';
import 'package:zyduspod/screens/no_internet_screen.dart';
import 'package:zyduspod/services/connectivity_service.dart';

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  
  const ConnectivityWrapper({
    super.key,
    required this.child,
  });

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    // Initialize connectivity service
    await _connectivityService.initialize();
    
    // Check initial connection status
    _isConnected = await _connectivityService.checkConnection();
    if (mounted) {
      setState(() {});
    }

    // Listen to connectivity changes
    _connectivityService.connectionStatusStream.listen((isConnected) {
      if (mounted && _isConnected != isConnected) {
        setState(() {
          _isConnected = isConnected;
        });

        // Show snackbar when connection is restored
        if (isConnected) {
          _showConnectionRestoredSnackbar();
        }
      }
    });
  }

  void _showConnectionRestoredSnackbar() {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Internet connection restored!'),
          ],
        ),
        backgroundColor: Color(0xFF4CAF50),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show no internet screen if not connected
    if (!_isConnected) {
      return const NoInternetScreen();
    }

    // Show normal content if connected
    return widget.child;
  }

  @override
  void dispose() {
    // Don't dispose the service as it's a singleton
    super.dispose();
  }
}

