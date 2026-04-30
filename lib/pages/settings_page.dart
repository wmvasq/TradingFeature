import 'package:flutter/material.dart';
import '../db_helper.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final DBHelper _dbHelper = DBHelper();

  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _saveMessage;
  Color _saveMessageColor = Colors.green;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    
    final apiKey = await _dbHelper.getAppConfig('minimax_api_key');
    final baseUrl = await _dbHelper.getAppConfig('minimax_base_url');
    final model = await _dbHelper.getAppConfig('minimax_model');

    setState(() {
      _apiKeyController.text = apiKey ?? '';
      _baseUrlController.text = baseUrl ?? 'https://api.minimax.io/v1';
      _modelController.text = model ?? 'MiniMax-M2.7-highspeed';
      _isLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    setState(() {
      _isSaving = true;
      _saveMessage = null;
    });

    try {
      await _dbHelper.saveAppConfig('minimax_api_key', _apiKeyController.text.trim());
      await _dbHelper.saveAppConfig('minimax_base_url', _baseUrlController.text.trim());
      await _dbHelper.saveAppConfig('minimax_model', _modelController.text.trim());

      setState(() {
        _saveMessage = 'Settings saved successfully!';
        _saveMessageColor = Colors.green;
        _isSaving = false;
      });
    } catch (e) {
      setState(() {
        _saveMessage = 'Error saving settings: $e';
        _saveMessageColor = Colors.red;
        _isSaving = false;
      });
    }
  }

  Future<void> _resetToDefaults() async {
    setState(() {
      _apiKeyController.text = '';
      _baseUrlController.text = 'https://api.minimax.io/v1';
      _modelController.text = 'MiniMax-M2.7-highspeed';
      _saveMessage = 'Reset to defaults (not saved yet)';
      _saveMessageColor = Colors.orange;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF000080),
        foregroundColor: const Color.fromARGB(255, 235, 212, 1),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MiniMax API Configuration',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF000080),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Configure your API connection settings',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  _buildTextField(
                    controller: _apiKeyController,
                    label: 'API Key',
                    hint: 'Enter your MiniMax API key',
                    obscureText: true,
                    icon: Icons.key,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _baseUrlController,
                    label: 'Base URL',
                    hint: 'e.g., https://api.minimax.io/v1',
                    icon: Icons.link,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _modelController,
                    label: 'Model',
                    hint: 'e.g., MiniMax-M2.7-highspeed',
                    icon: Icons.smart_toy,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Available models: MiniMax-M2.7-highspeed, MiniMax-M2.5-highspeed, etc.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  if (_saveMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _saveMessageColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _saveMessageColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _saveMessageColor == Colors.green
                                ? Icons.check_circle
                                : Icons.error,
                            color: _saveMessageColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _saveMessage!,
                              style: TextStyle(color: _saveMessageColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_saveMessage != null) const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveConfig,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF000080),
                        foregroundColor: const Color.fromARGB(255, 235, 212, 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _resetToDefaults,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reset to Defaults'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Database Info',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF000080),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Settings are stored locally in SQLite database (conversations.db)',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF000080)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, color: const Color(0xFF000080)),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF000080), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
