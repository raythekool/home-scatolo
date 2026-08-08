import 'package:flutter/material.dart';

import '../models/room.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final List<Room> _rooms = <Room>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stanze'),
      ),
      body: ListView.builder(
        itemCount: _rooms.length,
        itemBuilder: (BuildContext context, int index) {
          final Room room = _rooms[index];
          return ListTile(
            title: Text(room.name),
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
