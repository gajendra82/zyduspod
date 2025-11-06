import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyduspod/config.dart';

class MasterDataService {
  static final MasterDataService _instance = MasterDataService._internal();
  factory MasterDataService() => _instance;
  MasterDataService._internal();

  // Cache for master data
  List<Map<String, dynamic>> _hospitals = [];
  List<Map<String, dynamic>> _stockists = [];
  bool _hospitalsLoaded = false;
  bool _stockistsLoaded = false;

  /// Fetch all hospitals from the master API
  Future<List<Map<String, dynamic>>> getAllHospitals() async {
    if (_hospitalsLoaded && _hospitals.isNotEmpty) {
      return _hospitals;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http.get(
        Uri.parse(API_HOSPITALS_URL),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Hospitals API Response: ${response.statusCode}');
      print('Hospitals API Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Handle different response structures
        List<Map<String, dynamic>> hospitals = [];
        if (data is List) {
          hospitals = List<Map<String, dynamic>>.from(data);
        } else if (data['data'] != null) {
          hospitals = List<Map<String, dynamic>>.from(data['data']);
        } else if (data['hospitals'] != null) {
          hospitals = List<Map<String, dynamic>>.from(data['hospitals']);
        }

        _hospitals = hospitals;
        _hospitalsLoaded = true;
        
        print('Loaded ${hospitals.length} hospitals');
        return hospitals;
      } else {
        throw Exception('Failed to load hospitals: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading hospitals: $e');
      // Return mock data for development
      _hospitals = _getMockHospitals();
      _hospitalsLoaded = true;
      return _hospitals;
    }
  }

  /// Fetch all stockists from the master API
  Future<List<Map<String, dynamic>>> getAllStockists() async {
    if (_stockistsLoaded && _stockists.isNotEmpty) {
      return _stockists;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http.get(
        Uri.parse(API_STOCKISTS_URL),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Stockists API Response: ${response.statusCode}');
      print('Stockists API Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Handle different response structures
        List<Map<String, dynamic>> stockists = [];
        if (data is List) {
          stockists = List<Map<String, dynamic>>.from(data);
        } else if (data['data'] != null) {
          stockists = List<Map<String, dynamic>>.from(data['data']);
        } else if (data['stockists'] != null) {
          stockists = List<Map<String, dynamic>>.from(data['stockists']);
        }

        _stockists = stockists;
        _stockistsLoaded = true;
        
        print('Loaded ${stockists.length} stockists');
        return stockists;
      } else {
        throw Exception('Failed to load stockists: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading stockists: $e');
      _stockists = [];
      _stockistsLoaded = true;
      return [];
    }
  }

  /// Search hospitals by query
  Future<List<Map<String, dynamic>>> searchHospitals(String query) async {
    if (query.isEmpty) {
      return getAllHospitals();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final searchUrl = '${API_HOSPITALS_URL}?search=$query';
      final response = await http.get(
        Uri.parse(searchUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        List<Map<String, dynamic>> hospitals = [];
        if (data is List) {
          hospitals = List<Map<String, dynamic>>.from(data);
        } else if (data['data'] != null) {
          hospitals = List<Map<String, dynamic>>.from(data['data']);
        } else if (data['hospitals'] != null) {
          hospitals = List<Map<String, dynamic>>.from(data['hospitals']);
        }

        return hospitals;
      } else {
        // Fallback to local search if API search fails
        final allHospitals = await getAllHospitals();
        return allHospitals.where((hospital) {
          final name = (hospital['name'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase());
        }).toList();
      }
    } catch (e) {
      print('Error searching hospitals: $e');
      // Fallback to local search
      final allHospitals = await getAllHospitals();
      return allHospitals.where((hospital) {
        final name = (hospital['name'] ?? '').toString().toLowerCase();
        return name.contains(query.toLowerCase());
      }).toList();
    }
  }

  /// Search stockists by query
  Future<List<Map<String, dynamic>>> searchStockists(String query) async {
    if (query.isEmpty) {
      return getAllStockists();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final searchUrl = '${API_STOCKISTS_URL}?search=$query';
      final response = await http.get(
        Uri.parse(searchUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        List<Map<String, dynamic>> stockists = [];
        if (data is List) {
          stockists = List<Map<String, dynamic>>.from(data);
        } else if (data['data'] != null) {
          stockists = List<Map<String, dynamic>>.from(data['data']);
        } else if (data['stockists'] != null) {
          stockists = List<Map<String, dynamic>>.from(data['stockists']);
        }

        return stockists;
      } else {
        // Fallback to local search if API search fails
        final allStockists = await getAllStockists();
        return allStockists.where((stockist) {
          final name = (stockist['name'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase());
        }).toList();
      }
    } catch (e) {
      print('Error searching stockists: $e');
      // Fallback to local search
      final allStockists = await getAllStockists();
      return allStockists.where((stockist) {
        final name = (stockist['name'] ?? '').toString().toLowerCase();
        return name.contains(query.toLowerCase());
      }).toList();
    }
  }

  /// Get hospital name by ID
  String getHospitalNameById(String id) {
    final hospital = _hospitals.firstWhere(
      (h) => h['id'].toString() == id,
      orElse: () => {'name': 'Unknown Hospital'},
    );
    return hospital['name'] ?? 'Unknown Hospital';
  }

  /// Get stockist name by ID
  String getStockistNameById(String id) {
    final stockist = _stockists.firstWhere(
      (s) => s['id'].toString() == id,
      orElse: () => {'name': 'Unknown Stockist'},
    );
    return stockist['name'] ?? 'Unknown Stockist';
  }

  /// Clear cache and reload data
  Future<void> refreshData() async {
    _hospitals = [];
    _stockists = [];
    _hospitalsLoaded = false;
    _stockistsLoaded = false;
    
    await Future.wait([
      getAllHospitals(),
      getAllStockists(),
    ]);
  }

  /// Get hospital ID by name
  String? getHospitalIdByName(String name) {
    try {
      final hospital = _hospitals.firstWhere(
        (h) => h['name']?.toString().toLowerCase() == name.toLowerCase(),
      );
      return hospital['id']?.toString();
    } catch (e) {
      return null;
    }
  }

  /// Get stockist ID by name
  String? getStockistIdByName(String name) {
    try {
      final stockist = _stockists.firstWhere(
        (s) => s['name']?.toString().toLowerCase() == name.toLowerCase(),
      );
      return stockist['id']?.toString();
    } catch (e) {
      return null;
    }
  }

  /// Mock hospitals data for development
  List<Map<String, dynamic>> _getMockHospitals() {
    return [
      {
        'id': '1',
        'name': 'City Hospital',
        'hospital_name': 'City Hospital',
        'hospital_code': 'CH001',
        'location': 'Mumbai, Maharashtra',
        'address': 'Mumbai, Maharashtra',
        'contact_info': {
          'phone': '+91-22-12345678',
          'email': 'info@cityhospital.com'
        }
      },
      {
        'id': '2',
        'name': 'General Hospital',
        'hospital_name': 'General Hospital',
        'hospital_code': 'GH002',
        'location': 'Delhi, NCR',
        'address': 'Delhi, NCR',
        'contact_info': {
          'phone': '+91-11-87654321',
          'email': 'contact@generalhospital.com'
        }
      },
      {
        'id': '3',
        'name': 'Apollo Hospital',
        'hospital_name': 'Apollo Hospital',
        'hospital_code': 'AH003',
        'location': 'Bangalore, Karnataka',
        'address': 'Bangalore, Karnataka',
        'contact_info': {
          'phone': '+91-80-11223344',
          'email': 'info@apollohospital.com'
        }
      },
      {
        'id': '4',
        'name': 'Fortis Hospital',
        'hospital_name': 'Fortis Hospital',
        'hospital_code': 'FH004',
        'location': 'Chennai, Tamil Nadu',
        'address': 'Chennai, Tamil Nadu',
        'contact_info': {
          'phone': '+91-44-55667788',
          'email': 'contact@fortishospital.com'
        }
      },
      {
        'id': '5',
        'name': 'Max Hospital',
        'hospital_name': 'Max Hospital',
        'hospital_code': 'MH005',
        'location': 'Pune, Maharashtra',
        'address': 'Pune, Maharashtra',
        'contact_info': {
          'phone': '+91-20-99887766',
          'email': 'info@maxhospital.com'
        }
      },
    ];
  }
}
