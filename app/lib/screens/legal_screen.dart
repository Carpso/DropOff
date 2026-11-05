import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Full-screen privacy policy / terms of use, rendered from bundled Markdown.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.asset});

  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(asset),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done || !snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          return ListView(
            padding: const EdgeInsets.all(18),
            children: _blocks(snap.data!),
          );
        },
      ),
    );
  }

  static List<Widget> _blocks(String text) {
    final out = <Widget>[];
    StringBuffer? para;

    void flush() {
      if (para != null && para!.isNotEmpty) {
        out.add(Text(para!.toString().trim(), style: const TextStyle(fontSize: 14, height: 1.7)));
        para = null;
      }
    }

    for (final line in text.split('\n')) {
      if (line.startsWith('# ')) {
        flush();
        out.add(Text(line.substring(2), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)));
        out.add(const SizedBox(height: 14));
      } else if (line.startsWith('## ')) {
        flush();
        out.add(Text(line.substring(3), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)));
        out.add(const SizedBox(height: 10));
      } else if (line.startsWith('- ')) {
        flush();
        out.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('\u2022  ', style: TextStyle(fontSize: 14, height: 1.7)),
            Expanded(child: Text(line.substring(2), style: const TextStyle(fontSize: 14, height: 1.7))),
          ],
        ));
        out.add(const SizedBox(height: 6));
      } else if (line.isEmpty) {
        flush();
        out.add(const SizedBox(height: 10));
      } else {
        para ??= StringBuffer();
        para!.writeln(line);
      }
    }
    flush();
    return out;
  }
}
