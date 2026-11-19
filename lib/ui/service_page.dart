import 'package:flutter/material.dart';
import 'theme.dart';

class ServicePage extends StatelessWidget {
  const ServicePage({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: const [
        PageHead('Service', 'Installation and maintenance'),
        Panel(
          child: Text(
            'This section is waiting for its screens and details. Send the Service screenshots and it will be built to match.',
            style: TextStyle(color: C.mute),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
