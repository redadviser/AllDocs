import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app_constants.dart';
import '../screens/archive/archive_screen.dart';
import '../screens/docshelf/docshelf_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  final DocumentsService _documentsService = DocumentsService.local();
  late final PageController _pageController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _documentsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = AppTheme.highContrastMode.value;
    final screens = [
      DocshelfScreen(documentsService: _documentsService),
      ArchiveScreen(documentsService: _documentsService),
      ProfileScreen(documentsService: _documentsService),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: highContrast
                ? const [Colors.black, Colors.black]
                : const [AppTheme.background, AppTheme.backgroundBottom],
          ),
        ),
        child: SafeArea(
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _selectedIndex = index),
            children: screens,
          ),
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: Listenable.merge([
          AppTheme.primaryColor,
          AppTheme.highContrastMode,
        ]),
        builder: (context, child) {
          return _AllDocsNavBar(
            selectedIndex: _selectedIndex,
            onSelected: _selectPage,
          );
        },
      ),
    );
  }

  void _selectPage(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }
}

class _AllDocsNavBar extends StatelessWidget {
  const _AllDocsNavBar({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(color: AppTheme.border.withValues(alpha: 0.45)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.view_week_rounded,
              label: AppConstants.navShelf.tr(),
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
            _NavItem(
              icon: Icons.folder_rounded,
              label: AppConstants.navArchive.tr(),
              selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
            _NavItem(
              icon: Icons.person_rounded,
              label: AppConstants.navProfile.tr(),
              selected: selectedIndex == 2,
              onTap: () => onSelected(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.accent : AppTheme.dimText;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
