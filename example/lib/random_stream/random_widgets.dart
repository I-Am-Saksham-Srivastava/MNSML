import 'package:flutter/material.dart';
import 'package:example/random_stream/random_store.dart';
import 'package:mnsml/mnsml.dart';

class RandomNumberExample extends StatefulWidget {
  const RandomNumberExample({Key? key}) : super(key: key);

  @override
  State<RandomNumberExample> createState() => _RandomNumberExampleState();
}

class _RandomNumberExampleState extends State<RandomNumberExample> {
  final RandomStore store = RandomStore();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Random Number Generator')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text('Random number', style: TextStyle(color: Colors.grey)),
          Observer(
            builder: (_) {
              final value = store.randomStream.value;

              return Text(
                '${value ?? '---'}',
                style: const TextStyle(fontSize: 96),
              );
            },
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }
}
