import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ApiService api;
  const ProfileScreen({super.key, required this.api});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '';
  String _email = '';
  File? _localProfileImage;
  bool _loading = false;
  bool _isEditingName = false;
  bool _isUploadingImage = false;
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedImagePath = prefs.getString('user_profile_image_path');
    
    setState(() {
      _name = prefs.getString('user_name') ?? '';
      _email = prefs.getString('user_email') ?? '';
      
      // Restore saved image if exists and file is still there
      if (savedImagePath != null) {
        final file = File(savedImagePath);
        if (file.existsSync()) {
          _localProfileImage = file;
        } else {
          // If file no longer exists, remove the stored path
          prefs.remove('user_profile_image_path');
        }
      }
    });
  }

  Future<void> _updateName() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede estar vacío')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.api.updateProfile(_nameController.text.trim());
      
      // Update local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', _nameController.text.trim());
      
      setState(() {
        _name = _nameController.text.trim();
        _isEditingName = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre actualizado exitosamente')),
      );
    } catch (e) {
      // Handle token errors
      if (await _handleTokenError(e)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Cambiar Contraseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Contraseña actual',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Confirmar nueva contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                if (currentPasswordController.text.isEmpty ||
                    newPasswordController.text.isEmpty ||
                    confirmPasswordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Todos los campos son requeridos')),
                  );
                  return;
                }

                if (newPasswordController.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('La nueva contraseña debe tener al menos 6 caracteres')),
                  );
                  return;
                }

                if (newPasswordController.text != confirmPasswordController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Las contraseñas nuevas no coinciden')),
                  );
                  return;
                }

                setState(() => isLoading = true);
                try {
                  await widget.api.changePassword(
                    currentPasswordController.text,
                    newPasswordController.text,
                    confirmPasswordController.text,
                  );
                  
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contraseña actualizada exitosamente')),
                  );
                } catch (e) {
                  // Handle token errors
                  if (await _handleTokenError(e)) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                } finally {
                  setState(() => isLoading = false);
                }
              },
              child: isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cambiar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 500,
        maxHeight: 500,
      );

      if (image == null) return;

      setState(() => _isUploadingImage = true);

      try {
        // For now, we'll store the image locally
        // In the future, this can be extended to upload to server
        final file = File(image.path);
        
        // Save the image path to SharedPreferences for persistence
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_profile_image_path', file.path);
        
        setState(() {
          _localProfileImage = file;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil actualizada'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() => _isUploadingImage = false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Colores para tema claro: Celeste, Azul, Blanco, Gris, Negro
    final bgColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFE0F7FF); // Celeste muy claro
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1A1A1A); // Negro
    final secondaryTextColor = isDarkMode ? Colors.grey[400] : const Color(0xFF555555); // Gris
    const primaryBlue = Color(0xFF1976D2); // Azul
    
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Profile header with avatar
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Profile Image with Edit Button
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: _localProfileImage != null
                            ? ClipOval(
                                child: Image.file(
                                  _localProfileImage!,
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 50,
                              ),
                      ),
                      GestureDetector(
                        onTap: _isUploadingImage ? null : _pickAndUploadImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primaryBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: cardColor, width: 3),
                          ),
                          child: _isUploadingImage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 16,
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _name.isEmpty ? 'Usuario' : _name,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _email.isEmpty ? 'email@ejemplo.com' : _email,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDarkMode ? Colors.grey[400] : secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Profile information
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Información Personal',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Name field
                  Row(
                    children: [
                      const Icon(Icons.person_outline, color: Color(0xFF1976D2)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _isEditingName
                            ? TextField(
                                controller: _nameController,
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  labelText: 'Nombre',
                                  labelStyle: TextStyle(
                                    color: isDarkMode ? Colors.grey[400] : secondaryTextColor,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1976D2),
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
                                ),
                              )
                            : Text(
                                'Nombre: ${_name.isEmpty ? 'No especificado' : _name}',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: textColor,
                                ),
                              ),
                      ),
                      if (!_isEditingName)
                        IconButton(
                          onPressed: () {
                            _nameController.text = _name;
                            setState(() => _isEditingName = true);
                          },
                          icon: const Icon(Icons.edit, color: Color(0xFF1976D2)),
                        ),
                      if (_isEditingName) ...[
                        IconButton(
                          onPressed: _loading ? null : _updateName,
                          icon: _loading 
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                                  ),
                                )
                              : const Icon(Icons.check, color: Colors.green),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() => _isEditingName = false);
                          },
                          icon: const Icon(Icons.close, color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Email field (read-only)
                  Row(
                    children: [
                      const Icon(Icons.email_outlined, color: Color(0xFF1976D2)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Email: ${_email.isEmpty ? 'No especificado' : _email}',
                          style: TextStyle(
                            fontSize: 16,
                            color: textColor,
                          ),
                        ),
                      ),
                      Icon(Icons.lock, color: secondaryTextColor, size: 16),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Actions
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acciones',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Change password button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _showChangePasswordDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text(
                        'Cambiar Contraseña',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Preferences section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preferencias',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  SwitchListTile(
                    title: Text(
                      'Tema oscuro',
                      style: TextStyle(color: textColor),
                    ),
                    subtitle: Text(
                      'Activar modo oscuro',
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : secondaryTextColor,
                      ),
                    ),
                    value: Provider.of<ThemeProvider>(context, listen: true).isDarkMode,
                    onChanged: (value) {
                      Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
                    },
                    secondary: const Icon(Icons.dark_mode, color: Color(0xFF1976D2)),
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFF1976D2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// Handles invalid token errors by clearing session and redirecting to login.
  /// Returns true if the error was a token error, false otherwise.
  Future<bool> _handleTokenError(dynamic error) async {
    final errorMsg = error.toString().toLowerCase();
    
    if (errorMsg.contains('invalid token') || 
        errorMsg.contains('token expired') ||
        errorMsg.contains('missing bearer token') ||
        errorMsg.contains('missing auth token') ||
        errorMsg.contains('exception: invalid token')) {
      
      // Clear session
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      widget.api.clearToken();
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)),
          (route) => false,
        );
      }
      return true;
    }
    return false;
  }
}