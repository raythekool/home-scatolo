import 'package:material_ui/material_ui.dart';

import '../models/container.dart' as models;

/// Restituisce l'icona Material più adatta al tipo di contenitore.
IconData iconForContainerType(models.ContainerType type) {
  return switch (type) {
    models.ContainerType.armadio => Icons.door_sliding_outlined,
    models.ContainerType.scatolone => Icons.inventory_2_outlined,
    models.ContainerType.libreria => Icons.menu_book_outlined,
    models.ContainerType.cassetto => Icons.inbox_outlined,
  };
}
