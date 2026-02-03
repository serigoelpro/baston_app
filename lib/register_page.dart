import 'package:flutter/material.dart';

class RegisterPage extends StatefulWidget {
  RegisterPage({Key? key}) : super(key: key);

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    // TODO: Integra tu lógica real (Firebase, API, etc.)
    // ------ EJEMPLO (comentado) con FirebaseAuth ------
    // try {
    //   final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
    //     email: _emailCtrl.text.trim(),
    //     password: _passCtrl.text,
    //   );
    //   await cred.user?.updateDisplayName(
    //     '${_nameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
    //   );
    //   if (!mounted) return;
    //   Navigator.of(context).pop(); // volver al login o ir a Home
    // } on FirebaseAuthException catch (e) {
    //   _showMsg(e.message ?? 'No se pudo registrar');
    // } finally {
    //   if (mounted) setState(() => _loading = false);
    // }
    // ---------------------------------------------------

    await Future.delayed(const Duration(milliseconds: 900)); // demo
    if (!mounted) return;
    setState(() => _loading = false);
    _showMsg('Registro completado (demo)');
    Navigator.of(context).pop(); // vuelve al login
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8FB7EB), Color(0xFF7DA7E4)], // fondo azul
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 360,
              minWidth: size.width * 0.8,
            ),
            child: Card(
              elevation: 6,
              color: const Color(0xFFD4ECFA), // panel celeste claro
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Regístrate',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),

                        const Text('Nombre', style: TextStyle(fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Nombre',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre' : null,
                        ),
                        const SizedBox(height: 12),

                        const Text('Apellido', style: TextStyle(fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _lastNameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Apellido',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Ingresa tu apellido' : null,
                        ),
                        const SizedBox(height: 12),

                        const Text('Correo', style: TextStyle(fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Correo',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Ingresa tu correo';
                            final emailReg = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                            if (!emailReg.hasMatch(value)) return 'Correo inválido';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        const Text('Contraseña', style: TextStyle(fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure1,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: 'Contraseña',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              tooltip: _obscure1 ? 'Mostrar' : 'Ocultar',
                              icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure1 = !_obscure1),
                            ),
                          ),
                          validator: (v) {
                            final value = v ?? '';
                            if (value.isEmpty) return 'Ingresa una contraseña';
                            if (value.length < 6) return 'Mínimo 6 caracteres';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        const Text('Confirmar contraseña', style: TextStyle(fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _confirmCtrl,
                          obscureText: _obscure2,
                          decoration: InputDecoration(
                            hintText: 'Confirmar Contraseña',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              tooltip: _obscure2 ? 'Mostrar' : 'Ocultar',
                              icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure2 = !_obscure2),
                            ),
                          ),
                          validator: (v) {
                            if ((v ?? '').isEmpty) return 'Confirma tu contraseña';
                            if (v != _passCtrl.text) return 'Las contraseñas no coinciden';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        SizedBox(
                          height: 44,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Continuar'),
                          ),
                        ),

                        // Link: ya tienes cuenta
                        TextButton(
                          onPressed: () {
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop(); // volver al login
                            } else {
                              // Si entraste directo aquí, intenta ir a LoginPage si la tienes en rutas
                              // Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => LoginPage()));
                              _showMsg('Ir al inicio de sesión');
                            }
                          },
                          child: const Text('Ya tienes una cuenta?, Inicia sesión!'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
