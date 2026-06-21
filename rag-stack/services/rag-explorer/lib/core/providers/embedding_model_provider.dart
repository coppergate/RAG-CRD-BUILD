import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_config_provider.dart';

class EmbeddingModelNotifier extends Notifier<String> {
  @override
  String build() {
    final config = ref.watch(appConfigProvider);
    return config.availableEmbeddingModels.first;
  }

  void setModel(String model) {
    state = model;
  }
}

final embeddingModelProvider =
    NotifierProvider<EmbeddingModelNotifier, String>(EmbeddingModelNotifier.new);
