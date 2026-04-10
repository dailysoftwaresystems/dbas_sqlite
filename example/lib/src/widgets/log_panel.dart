import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LogPanel extends StatelessWidget {
  final List<String> entries;
  final ScrollController controller;
  final VoidCallback onClear;

  const LogPanel({
    super.key,
    required this.entries,
    required this.controller,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(top: BorderSide(color: Colors.grey[700]!)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Output',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 18),
                  onPressed: onClear,
                  tooltip: 'Clear log',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'No output yet. Tap an operation to begin.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      Color textColor = Colors.white70;
                      if (entry.contains('[ERROR]')) {
                        textColor = Colors.redAccent;
                      } else if (entry.contains('[OK]')) {
                        textColor = Colors.greenAccent;
                      }
                      return GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: entry));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied to clipboard'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Text(
                          entry,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
