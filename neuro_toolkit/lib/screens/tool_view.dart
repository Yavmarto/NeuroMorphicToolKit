import 'package:flutter/material.dart';
import 'package:neuro_toolkit/models/module.dart';

class ToolViewScreen extends StatefulWidget {
  final Module module;

  const ToolViewScreen({super.key, required this.module});

  @override
  State<ToolViewScreen> createState() => _ToolViewScreenState();
}

class _ToolViewScreenState extends State<ToolViewScreen> {
  final List<String> _logs = [];
  bool _isRunning = false;

  Future<void> _runTool() async {
    setState(() {
      _isRunning = true;
      _logs.add('--- Starting ${widget.module.name} ---');
      _logs.add('Initializing environment...');
    });

    // Mock execution process
    for (int i = 1; i <= 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _logs.add('Executing step $i/5: Processing data...');
      });
    }

    if (!mounted) return;
    setState(() {
      _logs.add('Execution completed successfully.');
      _logs.add('--- Finished ${widget.module.name} ---');
      _isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.module.name} Runner'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tool Execution Logs',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Text(
                      _logs[index],
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isRunning ? null : _runTool,
              child: _isRunning
                  ? const CircularProgressIndicator()
                  : const Text('Run Tool'),
            ),
          ],
        ),
      ),
    );
  }
}
