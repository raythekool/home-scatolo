import 'package:flutter/material.dart';

import '../models/container.dart' as models;

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> {
  final List<models.Container> _containers = <models.Container>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contenitori'),
      ),
      body: ListView.builder(
        itemCount: _containers.length,
        itemBuilder: (BuildContext context, int index) {
          final models.Container container = _containers[index];
          return ListTile(
            title: Text(container.name),
            subtitle: Text(container.type),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
