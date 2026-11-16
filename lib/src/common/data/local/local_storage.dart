import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences is initialized before runApp so providers never observe
/// a null value during the first frame.
class LocalStorage {
  static final LocalStorage _instance = LocalStorage._();
  static SharedPreferences? _preferences;

  factory LocalStorage() => _instance;

  LocalStorage._();

  static Future<void> initialize() async {
    _preferences ??= await SharedPreferences.getInstance();
  }

  SharedPreferences? getSharedPreferences() => _preferences;
}
