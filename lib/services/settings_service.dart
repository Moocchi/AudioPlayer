import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService with ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyCollectionLayout = 'collection_layout';

  String _collectionLayoutMode = 'grid'; // 'grid' or 'list'

  String get collectionLayoutMode => _collectionLayoutMode;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _collectionLayoutMode = prefs.getString(_keyCollectionLayout) ?? 'grid';
    notifyListeners();
  }

  Future<void> setCollectionLayoutMode(String mode) async {
    if (mode != 'grid' && mode != 'list') return;

    _collectionLayoutMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCollectionLayout, mode);
  }
}
