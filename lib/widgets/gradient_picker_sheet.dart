import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../models/gradient_config.dart';
import '../theme/app_theme.dart';

class GradientPickerSheet extends StatefulWidget {
  final PaletteGenerator palette;
  final GradientConfig? initialConfig;
  final String? coverImagePath; // For preview

  const GradientPickerSheet({
    super.key,
    required this.palette,
    this.initialConfig,
    this.coverImagePath,
  });

  @override
  State<GradientPickerSheet> createState() => _GradientPickerSheetState();
}

class _GradientPickerSheetState extends State<GradientPickerSheet> {
  late GradientType _selectedType;
  Color? _customColor1;
  Color? _customColor2;
  int _selectingColorIndex = 1;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialConfig?.type ?? GradientType.auto;
    _customColor1 = widget.initialConfig?.color1;
    _customColor2 = widget.initialConfig?.color2;
  }

  List<Color> get _paletteColors {
    final colors = widget.palette.colors.take(12).toList();
    return colors.isEmpty ? [AppTheme.primary] : colors;
  }

  List<Color> get _currentGradientColors {
    if (_selectedType == GradientType.auto) {
      // Get top 2 colors from palette
      final colors = _paletteColors;
      if (colors.length >= 2) {
        return [colors[0], colors[1]];
      } else if (colors.length == 1) {
        return [colors[0], AppTheme.background];
      }
      return [AppTheme.primary, AppTheme.background];
    } else {
      if (_customColor1 != null && _customColor2 != null) {
        return [_customColor1!, _customColor2!];
      }
      return [AppTheme.primary, AppTheme.background];
    }
  }

  Future<void> _pickCustomColor(int index) async {
    Color initialColor = AppTheme.primary;
    if (index == 1 && _customColor1 != null) {
      initialColor = _customColor1!;
    } else if (index == 2 && _customColor2 != null) {
      initialColor = _customColor2!;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Pick Color $index', style: AppTheme.heading2),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: initialColor,
            onColorChanged: (color) {
              setState(() {
                if (index == 1) {
                  _customColor1 = color;
                } else {
                  _customColor2 = color;
                }
              });
            },
            pickerAreaHeightPercent: 0.8,
            enableAlpha: false,
            displayThumbColor: true,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Done',
              style: TextStyle(color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _selectColor(Color color) {
    setState(() {
      if (_selectingColorIndex == 1) {
        _customColor1 = color;
        _selectingColorIndex = 2;
      } else {
        _customColor2 = color;
      }
    });
  }

  void _applyGradient() {
    GradientConfig config;
    if (_selectedType == GradientType.auto) {
      // Fix: For auto, we MUST save the resolved colors so they persist
      // otherwise PlaylistScreen will try to resolve them again without the palette
      final autoColors = _currentGradientColors;
      config = GradientConfig.auto(
        color1: autoColors.isNotEmpty ? autoColors[0] : null,
        color2: autoColors.length > 1 ? autoColors[1] : null,
      );
    } else {
      if (_customColor1 == null || _customColor2 == null) {
        Fluttertoast.showToast(
          msg: 'Please select 2 colors',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.black54,
          textColor: Colors.white,
        );
        return;
      }
      config = GradientConfig.custom(
        color1: _customColor1!,
        color2: _customColor2!,
      );
    }
    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom:
            MediaQuery.of(context).padding.bottom +
            100, // Safe from mini player
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Text('Choose Gradient', style: AppTheme.heading2),
            const SizedBox(height: 16),

            // Live Preview
            Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _currentGradientColors,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite, size: 64, color: Colors.white70),
                    const SizedBox(height: 8),
                    Text(
                      'Preview',
                      style: AppTheme.heading2.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Dropdown for gradient type
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.divider),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<GradientType>(
                  value: _selectedType,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down),
                  items: const [
                    DropdownMenuItem(
                      value: GradientType.auto,
                      child: Text('Auto (From Photo)', style: AppTheme.body),
                    ),
                    DropdownMenuItem(
                      value: GradientType.custom,
                      child: Text('Custom (2 Colors)', style: AppTheme.body),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedType = value!;
                      if (_selectedType == GradientType.custom &&
                          _customColor1 == null) {
                        _selectingColorIndex = 1;
                      }
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Custom mode UI
            if (_selectedType == GradientType.custom) ...[
              // Color selection boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildColorBox(1, _customColor1),
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.arrow_forward,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 16),
                  _buildColorBox(2, _customColor2),
                ],
              ),

              const SizedBox(height: 16),

              // Palette grid
              const Text('Pick from photo colors:', style: AppTheme.caption),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _paletteColors.map((color) {
                  final isSelected =
                      color == _customColor1 || color == _customColor2;
                  return GestureDetector(
                    onTap: () => _selectColor(color),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: AppTheme.primary, width: 3)
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Custom Color Picker Button
              const Text('Or pick any custom color:', style: AppTheme.caption),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickCustomColor(1),
                      icon: const Icon(Icons.palette, size: 18),
                      label: const Text('Custom Color 1'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickCustomColor(2),
                      icon: const Icon(Icons.palette, size: 18),
                      label: const Text('Custom Color 2'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Apply button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _applyGradient,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Apply Gradient',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorBox(int index, Color? color) {
    final isSelecting = _selectingColorIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectingColorIndex = index),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: color ?? AppTheme.divider,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelecting ? AppTheme.primary : AppTheme.divider,
            width: isSelecting ? 3 : 1,
          ),
        ),
        child: color == null
            ? Center(
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
