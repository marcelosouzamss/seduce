import 'package:flutter/material.dart';

import 'ads_screen.dart';
import 'directory_home_screen.dart';
import 'messages_list_screen.dart';
import 'payments_screen.dart';
import 'rankings_screen.dart';

/// Shell com barra inferior: Buscar, Mensagens, Anúncios, Pagamentos, Rankings.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => MainShellScreenState();

  /// Para outras telas pedirem troca de aba (ex.: ir a Buscar).
  static MainShellScreenState? tryState(BuildContext context) {
    return context.findAncestorStateOfType<MainShellScreenState>();
  }
}

class MainShellScreenState extends State<MainShellScreen> {
  int _index = 0;

  void goToBuscar() {
    setState(() => _index = 0);
  }

  void goToMensagens() {
    setState(() => _index = 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DirectoryHomeScreen(),
          MessagesListScreen(),
          AdsScreen(),
          PaymentsScreen(),
          RankingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Buscar',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Mensagens',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Anúncios',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Pagamentos',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: 'Rankings',
          ),
        ],
      ),
    );
  }
}
