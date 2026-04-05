import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService with ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyCollectionLayout = 'collection_layout';
  static const String _keyGridAutoHideOverlay = 'grid_auto_hide_overlay';

  String _collectionLayoutMode = 'grid'; // 'grid' or 'list'
  bool _gridAutoHideOverlay = false;

  String get collectionLayoutMode => _collectionLayoutMode;
  bool get gridAutoHideOverlay => _gridAutoHideOverlay;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _collectionLayoutMode = prefs.getString(_keyCollectionLayout) ?? 'grid';
    _gridAutoHideOverlay = prefs.getBool(_keyGridAutoHideOverlay) ?? false;
    notifyListeners();
  }

  Future<void> setCollectionLayoutMode(String mode) async {
    if (mode != 'grid' && mode != 'list') return;

    _collectionLayoutMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCollectionLayout, mode);
  }

  Future<void> setGridAutoHideOverlay(bool value) async {
    _gridAutoHideOverlay = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGridAutoHideOverlay, value);
  }
}
