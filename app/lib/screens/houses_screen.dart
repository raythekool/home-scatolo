import 'package:flutter/material.dart';

import '../models/house.dart';

class HousesScreen extends StatefulWidget {
  const HousesScreen({super.key});

  @override
  State<HousesScreen> createState() => _HousesScreenState();
}

class _HousesScreenState extends State<HousesScreen> {
  final List<House> _houses = <House>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Case'),
      ),
      body: ListView.builder(
        itemCount: _houses.length,
        itemBuilder: (BuildContext context, int index) {
          final House house = _houses[index];
          return ListTile(
            title: Text(house.name),
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
