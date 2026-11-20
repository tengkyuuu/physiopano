import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/theme_provider.dart';
import '../../motion/motion.dart';
import '../../theme/physiopano_tokens.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Shared
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  bool _isLogin = true;

  // Register-only fields
  final _nameCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String? _selectedCourse;
  String? _selectedYearLevel;
  String? _selectedSex;

  // Emergency contact fields (shown in registration)
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyEmailCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  late final TabController _tabCtrl;

  static const _courses = [
    'BS Computer Engineering',
    'BS Electrical Engineering',
    'BS Civil Engineering',
    'BS Mechanical Engineering',
    'BS Electronics Engineering',
    'BS Information Technology',
    'BS Computer Science',
    'BS Nursing',
    'BS Psychology',
    'BS Education',
    'BS Accountancy',
    'BS Business Administration',
    'BS Architecture',
    'Other',
  ];

  static const _yearLevels = ['1st Year', '2nd Year', '3rd Year', '4th Year', '5th Year'];
  static const _sexOptions = ['Male', 'Female', 'Prefer not to say'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() {
          _isLogin = _tabCtrl.index == 0;
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _studentIdCtrl.dispose();
    _ageCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyEmailCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email above first');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final result = await context.read<AuthService>().sendPasswordResetEmail(email);
    if (!mounted) return;
    setState(() { _loading = false; _error = result; });
    if (result == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (!_isLogin) {
      if (_selectedCourse == null) {
        setState(() => _error = 'Please select your course');
        return;
      }
      if (_selectedYearLevel == null) {
        setState(() => _error = 'Please select your year level');
        return;
      }
      if (_selectedSex == null) {
        setState(() => _error = 'Please select your sex');
        return;
      }
    }

    setState(() { _loading = true; _error = null; });

    final auth = context.read<AuthService>();
    String? result;

    if (_isLogin) {
      result = await auth.signIn(_emailCtrl.text, _passwordCtrl.text);
    } else {
      result = await auth.register(
        _emailCtrl.text,
        _passwordCtrl.text,
        displayName: _nameCtrl.text.trim(),
        studentId: _studentIdCtrl.text.trim(),
        course: _selectedCourse ?? '',
        yearLevel: _selectedYearLevel ?? '',
        age: int.tryParse(_ageCtrl.text.trim()) ?? 0,
        sex: _selectedSex ?? '',
        emergencyName: _emergencyNameCtrl.text.trim(),
        emergencyEmail: _emergencyEmailCtrl.text.trim(),
        emergencyPhone: _emergencyPhoneCtrl.text.trim(),
      );

      // The sign-up answers are persisted locally by the session gate
      // (AuthService keeps them until the gate takes them).
    }

    if (!mounted) return;
    setState(() { _loading = false; _error = result; });

    if (result == null && !_isLogin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created successfully! Setting up your profile…'),
          duration: Duration(seconds: 3),
        ),
      );
    }
    // Navigation is handled automatically by _AuthGate StreamBuilder on success.
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.deepBlack,
        body: AuroraBackground(
          child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: size.height < 700 ? 12 : 24,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: size.height < 700 ? 12 : 24),

                  // Brand row: app tile + wordmark.
                  Reveal(
                    child: Row(
                      children: [
                        const BrandTile(size: 52),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PHYSIOPAÑO',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                            Text('Wearable wellbeing', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Hero: eyebrow + tight headline, Paño waving beside it.
                  Reveal(
                    index: 1,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: FadeThroughSwitcher(
                            child: PaperHeading(
                              key: ValueKey(_isLogin),
                              eyebrow: _isLogin ? 'Good to see you again' : 'A little closer to yourself',
                              title: _isLogin ? 'Welcome back.' : 'Nice to meet you.',
                              titleStyle: Theme.of(context).textTheme.displaySmall,
                            ),
                          ),
                        ),
                        const PanoMascot(mood: PanoMood.wave, size: 96, prop: PanoProp.heart),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Reveal(
                    index: 2,
                    child: Text(
                      'PHYSIOPAÑO listens to your body, so you can listen to yourself.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // ── Tab bar ─────────────────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(PpRadius.pill),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
                      boxShadow: PpShadow.raised(PpColors.light, lift: 0.6),
                    ),
                    child: TabBar(
                      controller: _tabCtrl,
                      labelColor: AppColors.onBrand,
                      splashBorderRadius: BorderRadius.circular(PpRadius.pill),
                      unselectedLabelColor: AppColors.textMuted,
                      labelStyle: PpTheme.font(weight: FontWeight.w700, size: 15),
                      unselectedLabelStyle: PpTheme.font(weight: FontWeight.w500, size: 15),
                      indicator: BoxDecoration(
                        gradient: AppColors.buttonGradient,
                        borderRadius: BorderRadius.circular(PpRadius.pill),
                        boxShadow: PpShadow.brand(PpColors.light),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      padding: const EdgeInsets.all(4),
                      tabs: const [
                        Tab(text: 'Sign In'),
                        Tab(text: 'Register'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Error banner ────────────────────────────────────────────
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.danger, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Fields ──────────────────────────────────────────────────
                  FadeThroughSwitcher(
                    child: KeyedSubtree(
                      key: ValueKey(_isLogin),
                      child: _isLogin ? _buildLoginFields() : _buildRegisterFields(),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Submit button ───────────────────────────────────────────
                  PillButton(
                    label: _isLogin ? 'Sign in' : 'Create my account',
                    trailingIcon: _loading ? null : Icons.arrow_forward_rounded,
                    busy: _loading,
                    onPressed: _loading ? null : _submit,
                  ),

                  if (_isLogin) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: _forgotPassword,
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.emerald,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildLoginFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          controller: _emailCtrl,
          label: 'Email Address',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter your email';
            if (!v.contains('@')) return 'Enter a valid email';
            return null;
          },
        ),
        const SizedBox(height: 14),
        _Field(
          controller: _passwordCtrl,
          label: 'Password',
          icon: Icons.lock_outline,
          obscureText: _obscure,
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: AppColors.textMuted,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter your password';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildRegisterFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          controller: _nameCtrl,
          label: 'Full Name',
          icon: Icons.person_outline,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Enter your full name';
            return null;
          },
        ),
        const SizedBox(height: 14),
        _Field(
          controller: _studentIdCtrl,
          label: 'Student ID',
          icon: Icons.badge_outlined,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Enter your student ID';
            return null;
          },
        ),
        const SizedBox(height: 14),

        // Course dropdown
        _Dropdown(
          value: _selectedCourse,
          label: 'Course / Program',
          icon: Icons.school_outlined,
          items: _courses,
          onChanged: (v) => setState(() => _selectedCourse = v),
        ),
        const SizedBox(height: 14),

        // Year Level + Sex in a row
        Row(
          children: [
            Expanded(
              child: _Dropdown(
                value: _selectedYearLevel,
                label: 'Year Level',
                icon: Icons.calendar_today_outlined,
                items: _yearLevels,
                onChanged: (v) => setState(() => _selectedYearLevel = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Dropdown(
                value: _selectedSex,
                label: 'Sex',
                icon: Icons.person_2_outlined,
                items: _sexOptions,
                onChanged: (v) => setState(() => _selectedSex = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Age field
        _Field(
          controller: _ageCtrl,
          label: 'Age',
          icon: Icons.cake_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter your age';
            final age = int.tryParse(v);
            if (age == null || age < 15 || age > 80) return 'Enter a valid age';
            return null;
          },
        ),
        const SizedBox(height: 14),

        _Field(
          controller: _emailCtrl,
          label: 'Email Address',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter your email';
            if (!v.contains('@')) return 'Enter a valid email';
            return null;
          },
        ),
        const SizedBox(height: 14),
        _Field(
          controller: _passwordCtrl,
          label: 'Password',
          icon: Icons.lock_outline,
          obscureText: _obscure,
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: AppColors.textMuted,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter a password';
            if (v.length < 6) return 'At least 6 characters required';
            return null;
          },
        ),

        const SizedBox(height: 24),

        // ── Emergency Contact ────────────────────────────────────────────
        const Row(
          children: [
            Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Emergency Contact (Optional)',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
            Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Someone you trust. PHYSIOPAÑO never contacts them on its own.',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        _Field(
          controller: _emergencyNameCtrl,
          label: 'Contact Name',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 14),
        _Field(
          controller: _emergencyEmailCtrl,
          label: 'Contact Email',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _Field(
          controller: _emergencyPhoneCtrl,
          label: 'Contact Phone',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),

        const SizedBox(height: 10),
        const Text(
          'Your data will only be used for research purposes and kept confidential.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Reusable field widget ────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      inputFormatters: inputFormatters,
      style: PpTheme.font(color: AppColors.textPrimary, size: 16, weight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textMuted),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.cardDarkAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PpRadius.control),
          borderSide: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PpRadius.control),
          borderSide: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PpRadius.control),
          borderSide: const BorderSide(color: AppColors.emerald, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PpRadius.control),
          borderSide: const BorderSide(color: AppColors.danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PpRadius.control),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        errorStyle: const TextStyle(color: AppColors.danger, fontSize: 11),
      ),
      validator: validator,
    );
  }
}

// ── Reusable dropdown widget ─────────────────────────────────────────────────
class _Dropdown extends StatelessWidget {
  final String? value;
  final String label;
  final IconData icon;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _Dropdown({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
      ),
      dropdownColor: AppColors.cardDarkAlt,
      icon: const Icon(Icons.keyboard_arrow_down_rounded,
          color: AppColors.textMuted, size: 18),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.cardDarkAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PpRadius.control),
          borderSide: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PpRadius.control),
          borderSide: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PpRadius.control),
          borderSide: const BorderSide(color: AppColors.emerald, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      items: items
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
