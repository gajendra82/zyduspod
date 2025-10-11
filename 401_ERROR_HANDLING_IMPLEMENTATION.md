# 401 Unauthorized Error Handling Implementation

## Overview
This document describes the implementation of automatic logout and redirect to login when the API returns a 401 (Unauthorized) error.

## Components Created

### 1. AuthService (`lib/services/auth_service.dart`)
A centralized authentication service that handles:
- User logout functionality
- Clearing authentication tokens and user data from SharedPreferences
- Automatic navigation to login screen
- Authentication status checks

**Key Methods:**
- `logout(BuildContext? context)`: Clears auth data and navigates to login
- `isAuthenticated()`: Check if user has valid token
- `getAuthToken()`: Retrieve stored token
- `getUserEmail()`: Retrieve user email
- `getUserName()`: Retrieve user name

### 2. ApiClient (`lib/services/api_client.dart`)
A singleton HTTP client wrapper that automatically handles 401 errors for all API calls.

**Features:**
- Wraps all HTTP methods (GET, POST, PUT, DELETE)
- Automatically adds Authorization headers
- Intercepts 401 responses and triggers logout
- Maintains context for navigation
- Throws custom `UnauthorizedException` for proper error handling

**Key Methods:**
- `setContext(BuildContext? context)`: Set navigation context
- `get()`, `post()`, `put()`, `delete()`: HTTP methods with 401 handling
- `send()`: Multipart request handling

## Services Updated

### 1. PodDetailsService
✅ Updated to use `ApiClient` instead of direct `http` calls
✅ Removed manual token retrieval
✅ Automatic 401 handling

### 2. HospitalDashboardService  
✅ Updated to use `ApiClient`
✅ All methods now handle 401 automatically

### 3. SalesService
✅ Updated to use `ApiClient`
✅ All API methods refactored

## UI Updates

### 1. MainNavigation (`lib/screens/main_navigation.dart`)
✅ Sets ApiClient context in `initState()` and `didChangeDependencies()`
✅ Ensures ApiClient always has valid navigation context

### 2. ProfileScreen (`lib/screens/profile_screen.dart`)
✅ Updated logout functionality to use `AuthService.logout()`
✅ Updated delete account to use `AuthService.logout()`
✅ Consistent logout behavior across the app

## How It Works

### Flow Diagram
```
User makes API request
    ↓
ApiClient intercepts request
    ↓
Adds Authorization header
    ↓
Sends request to server
    ↓
Server returns 401?
    ↓ YES
AuthService.logout() called
    ↓
Clear SharedPreferences
    ↓
Navigate to LoginScreen
    ↓
Show error message (optional)
```

### Example Usage

#### Before (Old Code)
```dart
final prefs = await SharedPreferences.getInstance();
final token = prefs.getString('authToken');

final response = await http.get(
  Uri.parse('$API_BASE_URL/pods/$podId'),
  headers: {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  },
);

if (response.statusCode == 401) {
  // Manual logout handling
  await prefs.remove('authToken');
  Navigator.pushReplacement(...);
}
```

#### After (New Code)
```dart
final ApiClient _apiClient = ApiClient();

final response = await _apiClient.get(
  Uri.parse('${API_BASE_URL}pods/$podId'),
);

// 401 is automatically handled!
// User is logged out and redirected to login
```

## Benefits

1. **Centralized Logic**: All 401 handling in one place
2. **Consistent Behavior**: Same logout flow everywhere
3. **Reduced Boilerplate**: No need to check 401 in every service
4. **Maintainable**: Easy to update logout logic
5. **Type Safe**: Custom exceptions for better error handling
6. **Context Aware**: Automatic navigation without passing context everywhere

## Testing Recommendations

### Manual Testing
1. **Normal Flow**: Login → Make API calls → Should work normally
2. **Token Expiry**: 
   - Login successfully
   - Manually expire/delete token on server
   - Make any API call
   - Should auto-logout and redirect to login
3. **Multiple 401s**: Ensure multiple 401s don't cause navigation issues
4. **Profile Logout**: Test manual logout from profile screen

### Edge Cases to Test
- [ ] 401 during app initialization
- [ ] Multiple simultaneous API calls getting 401
- [ ] 401 while on login screen (should not redirect)
- [ ] Navigation context null scenarios
- [ ] Rapid successive API calls after token expiry

## Migration Guide for Future Services

When creating a new service that makes API calls:

1. Import the ApiClient:
```dart
import 'package:zyduspod/services/api_client.dart';
```

2. Create an instance:
```dart
class MyNewService {
  final ApiClient _apiClient = ApiClient();
  
  Future<Data> fetchData() async {
    final response = await _apiClient.get(
      Uri.parse('${API_BASE_URL}my-endpoint'),
    );
    // Handle response...
  }
}
```

3. Don't worry about:
   - ❌ Manual token retrieval
   - ❌ Authorization headers
   - ❌ 401 error checking
   - ❌ Logout logic

## Configuration

### Setting Context
The ApiClient context is automatically set in `MainNavigation`. If you need to set it elsewhere:

```dart
final ApiClient _apiClient = ApiClient();

@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _apiClient.setContext(context);
  });
}
```

### Customizing Logout Behavior
To modify logout behavior, edit `AuthService.logout()` method:

```dart
static Future<void> logout(BuildContext? context) async {
  // Add custom logic here
  // Example: Call logout API endpoint
  // Example: Clear additional cache
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear(); // Or remove specific keys
  
  if (context != null && context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}
```

## Security Considerations

1. **Token Storage**: Tokens are stored in SharedPreferences (secure on both iOS and Android)
2. **Complete Cleanup**: All auth data is cleared on logout
3. **Immediate Action**: 401 triggers instant logout, preventing unauthorized access
4. **No Token Exposure**: Tokens are never logged or exposed in error messages

## Future Enhancements

Consider implementing:
- [ ] Automatic token refresh before expiry
- [ ] Offline queue for failed requests
- [ ] Retry mechanism for network errors
- [ ] Biometric re-authentication
- [ ] Remember me functionality
- [ ] Session timeout warnings
- [ ] Activity tracking for auto-logout

## Troubleshooting

### Issue: User not redirected on 401
**Solution**: Ensure `ApiClient.setContext()` is called in MainNavigation

### Issue: Multiple logout dialogs
**Solution**: The implementation prevents this, but check for duplicate ApiClient instances

### Issue: Context null error
**Solution**: Ensure context is set before making API calls

## Files Modified

- ✅ `lib/services/auth_service.dart` (NEW)
- ✅ `lib/services/api_client.dart` (NEW)
- ✅ `lib/services/pod_details_service.dart` (MODIFIED)
- ✅ `lib/services/hospital_dashboard_service.dart` (MODIFIED)
- ✅ `lib/services/sales_service.dart` (MODIFIED)
- ✅ `lib/screens/main_navigation.dart` (MODIFIED)
- ✅ `lib/screens/profile_screen.dart` (MODIFIED)

## Conclusion

This implementation provides a robust, maintainable solution for handling authentication errors across the entire application. All API calls are now protected, and users will be automatically logged out and redirected to the login screen when their session expires.

