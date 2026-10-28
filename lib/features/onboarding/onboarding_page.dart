import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../widgets/warm_background.dart';

/// Layar perkenalan (sekali saja): apa yang dilakukan aplikasi & bahwa semua
/// analisis berjalan di HP.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide(this.icon, this.title, this.body);
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  static const _slides = [
    _Slide(Icons.shield_rounded, 'Penjaga pesan pribadimu',
        'Kenali pesan penipuan di WhatsApp sebelum kamu membalas, mentransfer, atau membuka tautan.'),
    _Slide(Icons.android_rounded, 'Periksa APK sebelum dipasang',
        'File undangan, resi, atau surat tilang berformat APK dinilai risikonya tanpa dijalankan.'),
    _Slide(Icons.lock_rounded, 'Semua dianalisis di HP ini',
        'IndoBERT berjalan di perangkatmu. Isi chat tidak dikirim ke server mana pun.'),
  ];

  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() => ref.read(settingsProvider.notifier).completeOnboarding();

  void _next() {
    if (_page == _slides.length - 1) {
      _finish();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _page == _slides.length - 1;
    return WarmBackground(
      intensity: 1,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: AppColors.ink),
                      child: const Icon(Icons.shield_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Penjaga Pesan',
                          style: theme.textTheme.titleMedium?.copyWith(color: AppColors.ink)),
                    ),
                    if (!last)
                      TextButton(
                        onPressed: _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.ink,
                          backgroundColor: Colors.white.withValues(alpha: 0.45),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Lewati'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? AppColors.ink
                            : AppColors.ink.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.ink),
                  onPressed: _next,
                  child: Text(last ? 'Mulai' : 'Lanjut'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          _GlassEmblem(icon: slide.icon),
          const Spacer(),
          Text(slide.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(color: AppColors.ink)),
          const SizedBox(height: 12),
          Text(slide.body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: AppColors.ink.withValues(alpha: 0.75), height: 1.45)),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

/// Emblem "kaca" oranye: lingkaran bercahaya + ikon bergradasi.
class _GlassEmblem extends StatelessWidget {
  final IconData icon;
  const _GlassEmblem({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ]),
      ),
      child: Center(
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFE3C9), AppColors.apricot, Color(0xFFE8430E)],
          ).createShader(r),
          child: Icon(icon, size: 210, color: Colors.white),
        ),
      ),
    );
  }
}
