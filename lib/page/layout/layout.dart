import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import './chat_page/chat_page.dart';
import 'sidebar.dart';
import './widgets/top_toolbar.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:chatmcp/provider/chat_model_provider.dart';
import 'package:chatmcp/utils/platform.dart';
import 'package:chatmcp/utils/color.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:chatmcp/page/setting/setting.dart';

class LayoutPage extends StatefulWidget {
  const LayoutPage({super.key});

  @override
  State<LayoutPage> createState() => _LayoutPageState();
}

class _LayoutPageState extends State<LayoutPage> {
  bool hideSidebar = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final llms = await ProviderManager.settingsProvider.loadSettings();
      if (llms.isNotEmpty) {
      } else if (mounted) {
        _showSettingsDialog(context);
      }
    });
  }

  void _handleWindowResize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 500 && !hideSidebar) {
      setState(() {
        hideSidebar = true;
      });
    }
  }

  void _toggleSidebar() {
    setState(() {
      hideSidebar = !hideSidebar;
    });
  }

  void _showSettingsDialog(BuildContext context) {
    if (kIsMobile) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingPage()));
    } else {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline.withAlpha(77),
              width: 1,
            ),
          ),
          elevation: 8,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: const SettingPage(),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildLayout() {
    return Scaffold(
      backgroundColor: AppColors.getLayoutBackgroundColor(context),
      drawer: (kIsMobile || (kIsBrowser && MediaQuery.of(context).size.width < 768))
          ? Builder(
              builder: (BuildContext context) => Theme(
                data: Theme.of(context),
                child: Container(
                  width: 250,
                  color: AppColors.getThemeBackgroundColor(context),
                  child: SafeArea(child: SidebarPanel(onToggle: () {})),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Row(
          children: [
            if ((kIsDesktop || kIsWeb) && !hideSidebar)
              Container(
                width: 250,
                color: AppColors.getSidebarBackgroundColor(context),
                child: SidebarPanel(onToggle: _toggleSidebar),
              ),
            Expanded(
              child: Column(
                children: [
                  TopToolbar(hideSidebar: hideSidebar, onToggleSidebar: _toggleSidebar),
                  Expanded(child: ChatPage()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsDesktop || kIsWeb) {
      _handleWindowResize(context);
    }

    return Consumer<ChatModelProvider>(
      builder: (context, chatModelProvider, child) {
        return kIsMobile
            ? KeyboardDismisser(gestures: [GestureType.onTap, GestureType.onPanUpdateDownDirection], child: _buildLayout())
            : _buildLayout();
      },
    );
  }
}
